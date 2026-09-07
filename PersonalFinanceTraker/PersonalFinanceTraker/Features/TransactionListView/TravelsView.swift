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
    /// Handed up to Activity, which owns the presentation the Add form comes from.
    let onAddExpense: (UUID) -> Void

    @Environment(TransactionListViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddSheet = false
    @State private var selectedTravel: TravelSummary?
    @State private var pendingDeletion: TravelSummary?
    /// Same two-step as Activity: ask on dismissal, never while a sheet is going down.
    @State private var pendingAddExpenseTravelId: UUID?

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
                            selectedTravel = summary
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
                            Button {
                                pendingDeletion = summary
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .appBackground()
        .navigationTitle("Travels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Always a sheet, so there's no back button to fall back on — same explicit
            // close as RecurringView.
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
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
        .sheet(isPresented: $showingAddSheet) {
            TravelFormSheet { name, symbolName in
                viewModel.addTravel(name: name, symbolName: symbolName)
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
