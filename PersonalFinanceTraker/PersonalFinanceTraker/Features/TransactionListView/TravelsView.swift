//
//  TravelsView.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// Lists every travel, newest trip first. This screen answers "what trips do I have" —
/// the Activity list can only show a travel where it falls chronologically, so an older
/// trip sinks out of reach as soon as you take another one.
///
/// Presented as a sheet that owns its own nested detail sheet, matching `RecurringView`.
struct TravelsView: View {
    /// What tapping a row means. Both modes are the same list of the same trips — the
    /// multi-select flow used to have a second, thinner sheet of its own, which meant two
    /// components to keep in step for one job.
    enum Mode {
        /// Opened from the ⋯ menu: a row opens the trip.
        case browse
        /// Opened from the selection bar: a row moves the selected transactions into it.
        case movingSelection
    }

    var mode: Mode = .browse
    /// Handed up to Activity, which owns the presentation the Add form comes from.
    /// Browse mode only — there is no "add expense" from inside a move.
    var onAddExpense: (UUID) -> Void = { _ in }

    /// Seeded by the caller rather than read here, because the height of this sheet depends
    /// on it: the detent is resolved on the first body evaluation, which happens *before*
    /// `.task`/`.onAppear` could fill it in, and changing the detent set afterwards does
    /// not re-resolve the height already committed to.
    init(
        mode: Mode = .browse,
        selectionHasTravel: Bool = false,
        onAddExpense: @escaping (UUID) -> Void = { _ in }
    ) {
        self.mode = mode
        self.onAddExpense = onAddExpense
        // initialValue, not `=`: later re-evaluations must not reset it. `bulkSetTravel`
        // clears the selection synchronously, so a live read would drop the button — and
        // shrink the sheet — mid-dismissal.
        _selectionHasTravel = State(initialValue: selectionHasTravel)
    }

    @Environment(TransactionListViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddSheet = false
    @State private var selectedTravel: TravelSummary?
    @State private var pendingDeletion: TravelSummary?
    /// Same two-step as Activity: ask on dismissal, never while a sheet is going down.
    @State private var pendingAddExpenseTravelId: UUID?
    /// Create-then-move, deferred the same way: the travel form is a sheet on top of this
    /// one, and closing both in the same turn drops the second dismissal.
    @State private var pendingCreation: (name: String, symbol: String)?

    /// Snapshot taken at init — see the initializer.
    @State private var selectionHasTravel: Bool

    private var isMoving: Bool { mode == .movingSelection }

    /// ponytail: a scaled constant instead of measuring the list. TravelRowView is a fixed
    /// two-line row, and @ScaledMetric already tracks Dynamic Type — measuring a List's
    /// content height means fighting the fact that a List reports the space it was *given*.
    /// If a travel name ever wraps to a second line the row outgrows this; .large is the
    /// escape hatch, and measurement is the upgrade path.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 62

    /// Height of the pinned Remove button. Unlike the old in-list row this is a number the
    /// view actually enforces with `.frame(height:)`, so the detent below is exact for it
    /// rather than guessing at section spacing.
    @ScaledMetric(relativeTo: .body) private var removeInsetHeight: CGFloat = 56

    /// Built from the same grouper the Activity list uses, so a travel's total and anchor
    /// date can never disagree between the two screens.
    private var summaries: [TravelSummary] {
        ActivityRowGrouper
            // Unlike Activity, this screen keeps empty travels: a trip you have created but
            // not spent on yet has to be findable, and this is the screen that lists them.
            .group(viewModel.transactions, travels: viewModel.travels, includeEmpty: true)
            .flatMap(\.1)
            .compactMap { if case .travel(let s) = $0 { return s } else { return nil } }
            .sorted { $0.anchorDate > $1.anchorDate }
    }

    /// The sheet opens at the height its rows actually need — one trip should not present
    /// a full-screen sheet with an empty two-thirds. Taller than the screen is clamped by
    /// the system, so a long list simply arrives full height, and .large stays draggable.
    private var contentDetent: PresentationDetent {
        // Inline title bar, list top inset, home indicator.
        let chrome: CGFloat = 110
        // The empty state is a card rather than rows; three rows' worth frames it.
        let rows = summaries.isEmpty ? 3 : summaries.count
        return .height(chrome + rowHeight * CGFloat(rows) + (showsRemoveRow ? removeInsetHeight : 0))
    }

    /// Untagging is offered only when the selection has something to untag.
    private var showsRemoveRow: Bool { isMoving && selectionHasTravel }

    var body: some View {
        Group {
            if summaries.isEmpty {
                // EmptyStateView is a compact card: without the explicit fill it centres
                // itself in the sheet and .appBackground() paints only behind the card.
                // Same treatment as RecurringView's empty state.
                EmptyStateView(
                    icon: "airplane",
                    message: "No travels yet",
                    subtitle: "Group a trip's expenses to see what the whole trip cost.",
                    actionTitle: "Add Travel",
                    action: { showingAddSheet = true }
                )
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else {
                List {
                    ForEach(summaries) { summary in
                        Button {
                            if isMoving {
                                viewModel.bulkSetTravel(summary.id)
                                dismiss()
                            } else {
                                selectedTravel = summary
                            }
                        } label: {
                            TravelRowView(travel: summary)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // Same constraint as Activity: presentation modifiers on a
                        // swipeActions button never present, so the dialog lives here.
                        .confirmationDialog(
                            "Delete \(summary.name)?",
                            isPresented: isDeletionPresented(for: summary),
                            titleVisibility: .visible
                        ) {
                            Button("Delete Travel", role: .destructive) {
                                viewModel.deleteTravel(id: summary.id)
                                pendingDeletion = nil
                            }
                            Button("Cancel", role: .cancel) { pendingDeletion = nil }
                        } message: {
                            Text("The \(TravelCountLabel.text(summary.count)) inside stay in your transactions — only the travel is removed.")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Not while moving: a destructive swipe inside a "pick one"
                            // sheet is a trap, and deleting the trip you are filing into
                            // is never what the gesture meant.
                            if !isMoving {
                                Button {
                                    pendingDeletion = summary
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }

                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        // Pinned below the list rather than being its last row: as a row it scrolled off
        // whenever the detent came up short, taking its own bottom padding with it, and it
        // had to be budgeted for in the detent as if it were a travel row. Here it is
        // always on screen and keeps the destructive action away from the pick-a-trip rows.
        .safeAreaInset(edge: .bottom) {
            if showsRemoveRow {
                Button("Remove from travel", role: .destructive) {
                    viewModel.bulkSetTravel(nil)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: removeInsetHeight)
            }
        }
        .appBackground()
        .presentationDetents([contentDetent, .large])
        .presentationDragIndicator(.visible)
        .navigationTitle(isMoving ? Text("Move to Travel") : Text("Travels"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Always a sheet, so there's no back button to fall back on — same explicit
            // close as RecurringView.
            ToolbarItem(placement: .cancellationAction) {
                Button(isMoving ? "Cancel" : "Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Travel"))
            }
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: flushPendingCreation) {
            TravelFormSheet { name, symbolName in
                if isMoving {
                    pendingCreation = (name, symbolName)
                } else {
                    viewModel.addTravel(name: name, symbolName: symbolName)
                }
            }
        }
        .sheet(item: $selectedTravel, onDismiss: flushPendingAddExpense) { summary in
            TravelDetailSheet(
                travel: summary,
                members: viewModel.members(of: summary),
                onAddExpense: {
                    pendingAddExpenseTravelId = summary.id
                    selectedTravel = nil
                },
                onSelect: { _ in selectedTravel = nil },
                onRemoveMember: { viewModel.removeFromTravel($0) },
                onRename: { name, symbolName in
                    viewModel.renameTravel(id: summary.id, name: name, symbolName: symbolName)
                    selectedTravel = nil
                },
                onDelete: { viewModel.deleteTravel(id: summary.id) }
            )
            .presentationBackground { AppBackground() }
        }
    }

    /// Hands the request up to Activity once the detail sheet is gone; Activity closes this
    /// screen in turn and only then asks for the Add form.
    /// Creates the travel and moves the selection into it once the form is fully gone,
    /// then closes this sheet too.
    private func flushPendingCreation() {
        guard let pendingCreation else { return }
        self.pendingCreation = nil
        viewModel.addTravelAndAssignSelection(name: pendingCreation.name, symbolName: pendingCreation.symbol)
        dismiss()
    }

    private func flushPendingAddExpense() {
        guard let travelId = pendingAddExpenseTravelId else { return }
        pendingAddExpenseTravelId = nil
        onAddExpense(travelId)
    }

    private func isDeletionPresented(for summary: TravelSummary) -> Binding<Bool> {
        Binding(
            get: { pendingDeletion?.id == summary.id },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}
