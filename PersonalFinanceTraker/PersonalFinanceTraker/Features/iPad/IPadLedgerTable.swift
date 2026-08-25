//
//  IPadLedgerTable.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

/// The iPad Activity screen: a real sortable, multi-selectable ledger rather than iPhone's
/// grouped card list.
///
/// This is the screen the "catching up on a backlog" use case actually needs — columns you can
/// sort, range-select with ⇧-click, and bulk-edit. iPhone's `ActivityView` is untouched and
/// stays the grouped list, which is the right shape for a narrow screen.
///
/// Everything here binds to the same `TransactionListViewModel` iPhone uses: the filtering,
/// bulk edits and recurrence-deletion scope logic are reused, not reimplemented.
struct IPadLedgerTable: View {
    @Environment(TransactionListViewModel.self) private var viewModel
    @Binding var showingAddItemView: Bool
    let materializationService: RecurrenceMaterializationService

    @State private var sortOrder = [KeyPathComparator(\TransactionSnapshot.timestamp, order: .reverse)]
    @State private var showCategorySheet = false
    @State private var showAmountSheet = false
    @State private var showNoteSheet = false
    @State private var showRecurringView = false
    @FocusState private var searchFocused: Bool

    private var rows: [TransactionSnapshot] {
        viewModel.filteredItems.sorted(using: sortOrder)
    }

    /// Written out rather than via `@Bindable` so the table's selection stays the view model's
    /// `selectedIDs` — the same set the bulk-edit actions already operate on.
    private var selection: Binding<Set<TransactionSnapshot.ID>> {
        Binding(
            get: { viewModel.selectedIDs },
            set: { viewModel.selectedIDs = $0 }
        )
    }

    private var searchText: Binding<String> {
        Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        )
    }

    // Split into three stages — ledger / dialogs / sheets. As one chain the type-checker times
    // out; this is purely a compile-time concern, the composition is unchanged.
    var body: some View {
        ledger
            .modifier(BulkEditSheets(
                showCategory: $showCategorySheet,
                showAmount: $showAmountSheet,
                showNote: $showNoteSheet,
                viewModel: viewModel
            ))
            .onAppear { viewModel.load() }
    }

    private var ledger: some View {
        table
            .tableStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: TransactionSnapshot.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            // Double-click / primary action opens the row in the shared inspector.
            if let id = ids.first, let item = rows.first(where: { $0.id == id }) {
                viewModel.transactionToEdit = item
            }
        }
        .navigationTitle("Activity")
        .searchable(text: searchText, prompt: "Search transactions...")
        .searchFocused($searchFocused)
        .keyboardAction("f", title: "Find") { searchFocused = true }
        // ⌘↵ rather than bare ↵: an unmodified Return would be stolen from the search field.
        .keyboardAction(.return, title: "Open") { openSelected() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRecurringView = true
                } label: {
                    Image(systemName: "repeat")
                }
                .accessibilityLabel(String(localized: "Recurring"))
            }
        }
        // A sheet, not a push: editing here opens in the shared inspector rather than a modal, so
        // there's no sheet-over-sheet conflict like iPhone's edit sheet has with the wizard.
        .sheet(isPresented: $showRecurringView) {
            NavigationStack { RecurringView(materializationService: materializationService) }
        }
        .appBackground()
        .overlay {
            if rows.isEmpty {
                emptyState
            }
        }
        .safeAreaInset(edge: .top) {
            filterChipsHeader
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.selectedIDs.isEmpty {
                selectionBar
            }
        }
        .confirmationDialog(
            "This is part of a recurring series",
            isPresented: recurringDeletionPresented,
            titleVisibility: .visible
        ) {
            Button("This transaction", role: .destructive) {
                viewModel.applyRecurrenceDeletionScope(.thisOnly)
            }
            Button("This and future", role: .destructive) {
                viewModel.applyRecurrenceDeletionScope(.thisAndFuture)
            }
            Button("Cancel", role: .cancel) { viewModel.pendingRecurrenceDeletion = nil }
        }
    }

    /// The three bulk-edit sheets, reused as-is from the iPhone Activity screen.
    private struct BulkEditSheets: ViewModifier {
        @Binding var showCategory: Bool
        @Binding var showAmount: Bool
        @Binding var showNote: Bool
        let viewModel: TransactionListViewModel

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: $showCategory) {
                    BulkCategoryPickerSheet(repo: viewModel.repo) { category in
                        viewModel.bulkSetCategory(category)
                        showCategory = false
                    }
                    .presentationBackground { AppBackground() }
                }
                .sheet(isPresented: $showAmount) {
                    AmountBulkEditSheet(count: viewModel.selectedIDs.count) { magnitude in
                        viewModel.bulkSetAmount(Decimal(magnitude))
                        showAmount = false
                    }
                    .presentationBackground { AppBackground() }
                }
                .sheet(isPresented: $showNote) {
                    DescriptionBulkEditSheet(count: viewModel.selectedIDs.count) { note in
                        viewModel.bulkSetNote(note)
                        showNote = false
                    }
                    .presentationBackground { AppBackground() }
                }
        }
    }

    // MARK: - Table

    /// Split out from `body`, and every cell extracted into its own small view, because the
    /// combined `Table` + four columns + modifier chain repeatedly blew the type-checker's
    /// time budget as one expression.
    private var table: some View {
        Table(rows, selection: selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.timestamp) { item in
                DateCell(date: item.timestamp)
            }
            .width(min: 80, ideal: 110, max: 150)

            TableColumn("Description", value: \.note) { item in
                DescriptionCell(note: item.note, category: item.category)
            }
            .width(min: 160)

            TableColumn("Category", value: \.category) { item in
                CategoryCell(
                    name: item.category,
                    systemImage: item.categorySystemImage,
                    colorToken: item.categoryColorToken
                )
            }
            .width(min: 140, ideal: 180)

            TableColumn("Amount", value: \.amount) { item in
                AmountCell(amount: item.amount, currencyCode: item.currencyCode)
            }
            .width(min: 110, ideal: 140, max: 200)
        }
    }

    // MARK: - Cells

    private struct DateCell: View {
        let date: Date

        var body: some View {
            Text(date, format: .dateTime.day().month(.abbreviated).year())
                .foregroundStyle(.textMid)
        }
    }

    private struct DescriptionCell: View {
        let note: String
        let category: String

        var body: some View {
            // Falls back to the category when there's no note — same rule the iPhone row uses.
            Text(note.isEmpty ? category : note)
                .foregroundStyle(.textPrimary)
        }
    }

    private struct CategoryCell: View {
        let name: String
        let systemImage: String?
        let colorToken: String?

        var body: some View {
            let icon = systemImage ?? CategoryInfo.info(for: name).symbol
            let tint = Color(categoryToken: colorToken ?? "categoryIndigo")
            return Label {
                Text(name).foregroundStyle(.textMid)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
        }
    }

    /// Extracted because inlining these in the `TableColumn` builder blew the type-checker's
    /// time budget.
    private struct AmountCell: View {
        let amount: Decimal
        let currencyCode: String

        var body: some View {
            // Always-signed: income reads "+€12,34", expenses "-€12,34". This matches
            // TransactionItemView on the Home screen and ImportResultView — the direction
            // of a transaction never depends on colour alone (WCAG 1.4.1).
            Text(amount, format: .currency(code: currencyCode).sign(strategy: .always()))
                .monospacedDigit()
                .foregroundStyle(amount < 0 ? Color.negative : Color.positive)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .privacyBlur()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.hasNoTransactions {
            EmptyStateView(
                icon: "tray",
                message: "No transactions yet",
                subtitle: "Add your first transaction to start tracking.",
                actionTitle: "Add Transaction",
                action: { showingAddItemView = true }
            )
        } else {
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    /// Persistent filter chip row moved out of toolbar so sheets don't cause it to
    /// disappear. The chips remain visible while their own popovers/sheets are presented.
    private var filterChipsHeader: some View {
        FilterChipsView()
            .background(Color.bg0)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text("\(viewModel.selectedIDs.count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.textMid)
            Spacer()
            Button("Category", systemImage: "tag") { showCategorySheet = true }
            Button("Amount", systemImage: "eurosign.circle") { showAmountSheet = true }
            Button("Description", systemImage: "text.alignleft") { showNoteSheet = true }
            Button("Delete", systemImage: "trash", role: .destructive) { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("Done") { viewModel.deselectAll() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<TransactionSnapshot.ID>) -> some View {
        if let id = ids.first, ids.count == 1, let item = rows.first(where: { $0.id == id }) {
            Button("Edit", systemImage: "pencil") { viewModel.transactionToEdit = item }
        }
        if !ids.isEmpty {
            Button("Set Category…", systemImage: "tag") {
                viewModel.selectedIDs = ids
                showCategorySheet = true
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                viewModel.selectedIDs = ids
                deleteSelected()
            }
        }
    }

    // MARK: - Actions

    /// Only for a single selection — opening the inspector on one of five selected rows would be
    /// a guess about which one the user meant.
    private func openSelected() {
        guard viewModel.selectedIDs.count == 1,
              let id = viewModel.selectedIDs.first,
              let item = rows.first(where: { $0.id == id }) else { return }
        viewModel.transactionToEdit = item
    }

    /// Routes through the same per-item delete iPhone uses so the recurring-series prompt still
    /// fires — a recurring row must not vanish before the user picks a scope.
    private func deleteSelected() {
        let selected = rows.filter { viewModel.selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        if let recurring = selected.first(where: { $0.recurrenceRuleId != nil }), selected.count == 1 {
            viewModel.pendingRecurrenceDeletion = recurring
            return
        }
        for item in selected where item.recurrenceRuleId == nil {
            viewModel.delete(item)
        }
        viewModel.deselectAll()
    }

    private var recurringDeletionPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingRecurrenceDeletion != nil },
            set: { if !$0 { viewModel.pendingRecurrenceDeletion = nil } }
        )
    }
}
