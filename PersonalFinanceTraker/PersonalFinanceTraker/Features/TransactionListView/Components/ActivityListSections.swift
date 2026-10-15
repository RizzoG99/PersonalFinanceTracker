import SwiftUI

/// Concrete section/row boundaries limit the type graph expanded by the list during
/// its first presentation. Actions and presentation state remain owned by Activity.
struct ActivitySummarySection: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    @Binding var showingAddItemView: Bool

    var body: some View {
        Section {
            if !viewModel.hasNoTransactions {
                FilterChipsView()
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if viewModel.totalFilteredIncome == 0 && viewModel.totalFilteredExpenses == 0 {
                if viewModel.hasNoTransactions {
                    EmptyStateView(
                        icon: "tray",
                        message: "No transactions yet",
                        subtitle: "Add your first transaction to start tracking.",
                        actionTitle: "Add Transaction",
                        action: { showingAddItemView = true }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                HStack(spacing: 12) {
                    StatCard(
                        icon: "arrow.down.left",
                        label: "Income",
                        value: viewModel.totalFilteredIncome.formattedEUR(),
                        color: .positive
                    )
                    StatCard(
                        icon: "arrow.up.right",
                        label: "Expenses",
                        value: viewModel.totalFilteredExpenses.formattedEUR(),
                        color: .negative
                    )
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
    }
}

struct ActivityDateSection: View {
    let dateString: String
    let rows: [ActivityRow]
    @Binding var selectedTravel: TravelSummary?
    @Binding var pendingTravelDeletion: TravelSummary?

    var body: some View {
        Section {
            ForEach(rows) { row in
                switch row {
                case .travel(let summary):
                    ActivityTravelRow(summary: summary, selectedTravel: $selectedTravel,
                                      pendingTravelDeletion: $pendingTravelDeletion)
                case .transaction(let item):
                    ActivityTransactionRow(item: item)
                }
            }
        } header: {
            Text(dateString)
                .font(.headline)
                .foregroundStyle(.textPrimary)
        }
    }
}

struct ActivityLoadMoreSection: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    let remainingRowCount: Int

    private var nextPageCount: Int {
        min(TransactionListViewModel.activityPageSize, remainingRowCount)
    }

    var body: some View {
        Section {
            Button {
                viewModel.loadNextActivityPage()
            } label: {
                Label {
                    Text(String(localized: "Show \(nextPageCount) more"))
                } icon: {
                    Image(systemName: "chevron.down")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .tint(.accentIndigo)
            .accessibilityHint(String(localized: "Loads the next \(nextPageCount) Activity items."))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }
}

struct ActivityTravelRow: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    let summary: TravelSummary
    @Binding var selectedTravel: TravelSummary?
    @Binding var pendingTravelDeletion: TravelSummary?

    var body: some View {
        Button {
            // Guarded for the same reason transaction rows guard: the button's tap fires on
            // *release*, so a long press would otherwise enter selection mode AND open the
            // detail sheet on top of it. No checkbox branch is needed here — selecting
            // expands travels into their members, so travel rows stop rendering entirely.
            if !viewModel.isSelecting {
                selectedTravel = summary
            }
        } label: {
            TravelRowView(travel: summary)
        }
        .buttonStyle(.plain)
        // Every other row in the list enters multi-select on a long press; a travel row
        // that ignores it reads as broken. Selecting expands travels, so what appears
        // under the finger is the members.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                if !viewModel.isSelecting {
                    viewModel.isSelecting = true
                }
            }
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        // On the row's own Button, not the swipe action: SwiftUI bridges swipeActions
        // content to UIContextualAction, and presentation modifiers attached there
        // silently fail to present — same constraint as the recurring dialog below.
        .confirmationDialog(
            "Delete \(summary.name)?",
            isPresented: isTravelDeletionPresented(for: summary),
            titleVisibility: .visible
        ) {
            Button("Delete Travel", role: .destructive) {
                viewModel.deleteTravel(id: summary.id)
                pendingTravelDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingTravelDeletion = nil }
        } message: {
            Text("The \(TravelCountLabel.text(summary.count)) inside stay in your transactions — only the travel is removed.")
        }
        // No full swipe, and a plain red button rather than role: .destructive — a
        // destructive-role swipe action plays the row-collapse animation immediately,
        // before the confirmation has been answered.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !viewModel.isSelecting {
                Button {
                    pendingTravelDeletion = summary
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }
    private func isTravelDeletionPresented(for summary: TravelSummary) -> Binding<Bool> {
        Binding(
            get: { pendingTravelDeletion?.id == summary.id },
            set: { if !$0 { pendingTravelDeletion = nil } }
        )
    }
}

struct ActivityTransactionRow: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    let item: TransactionSnapshot

    var body: some View {
        Button {
            if viewModel.isSelecting {
                viewModel.toggleSelection(item.id)
            } else {
                viewModel.transactionToEdit = item
            }
        } label: {
            HStack(spacing: 12) {
                if viewModel.isSelecting {
                    Image(systemName: viewModel.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedIDs.contains(item.id) ? Color.accentIndigo : Color.textMid)
                        .accessibilityHidden(true)
                }
                // Only this list badges travel membership: it is the one place a row in a
                // travel sits next to one that is not, and bulk-assigning silently moves
                // a row out of the travel it was already in.
                TransactionItemView(item: item, showsTravelBadge: true, travel: viewModel.travel(for: item))
            }
        }
        .buttonStyle(.plain)
        // The checkbox is hidden from VoiceOver, so without this a row sounds identical
        // whether or not it is selected — and the bar below offers Delete.
        .accessibilityAddTraits(
            viewModel.isSelecting && viewModel.selectedIDs.contains(item.id)
                ? AccessibilityTraits.isSelected
                : []
        )
        // A plain Button in a List swallows .onLongPressGesture, so run the
        // long-press alongside the button via .simultaneousGesture instead.
        // The long-press ONLY enters selection mode — the button's own tap
        // (which fires on release) then selects the pressed row. Toggling here
        // too would double-fire with that tap and cancel the selection.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                if !viewModel.isSelecting {
                    viewModel.isSelecting = true
                }
            }
        )
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        // Recurring rows must not use role: .destructive here — iOS plays the
        // swipe-to-delete row-collapse animation the instant a destructive-role
        // swipe action is tapped, regardless of whether the closure actually
        // deletes anything. For a recurring item we need to ask "this transaction"
        // vs. "this and future" first, so the row must stay put until the user
        // chooses; a plain button (red-tinted, no destructive role) avoids the
        // automatic collapse.
        //
        // The confirmationDialog itself must live on this row's main Button, not
        // on the swipeActions button — SwiftUI bridges swipeActions content to
        // UIContextualAction under the hood, and presentation modifiers attached
        // there silently fail to present.
        .confirmationDialog(
            "This is part of a recurring series",
            isPresented: isRecurringDeletionPresented(for: item),
            titleVisibility: .visible
        ) {
            Button("This transaction", role: .destructive) {
                viewModel.applyRecurrenceDeletionScope(.thisOnly)
            }
            Button("This and future", role: .destructive) {
                viewModel.applyRecurrenceDeletionScope(.thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingRecurrenceDeletion = nil
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: item.recurrenceRuleId == nil) {
            if !viewModel.isSelecting {
                if item.recurrenceRuleId != nil {
                    Button {
                        viewModel.pendingRecurrenceDeletion = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                } else {
                    Button(role: .destructive) {
                        viewModel.delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private func isRecurringDeletionPresented(for item: TransactionSnapshot) -> Binding<Bool> {
        Binding(
            get: { viewModel.pendingRecurrenceDeletion?.id == item.id },
            set: { if !$0 { viewModel.pendingRecurrenceDeletion = nil } }
        )
    }

}
