//
//  ActivityView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TransactionListViewModel.self) private var viewModel: TransactionListViewModel
    @Binding var showingAddItemView: Bool

    init(showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    @State private var showCategorySheet = false
    @State private var showAmountSheet = false
    @State private var showNoteSheet = false

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            List {
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

                ForEach(groupedFiltered, id: \.0) { dateString, dayItems in
                    Section {
                        ForEach(dayItems) { item in
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
                                    TransactionItemView(item: item)
                                }
                            }
                            .buttonStyle(.plain)
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
                    } header: {
                        Text(dateString)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }

                // Bottom spacing for floating tab bar — matches DashboardView and CompassView pattern
                Spacer(minLength: 80)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Activity")
            // Inline while selecting so the "N selected" principal item is visible
            // (a large title suppresses it).
            .navigationBarTitleDisplayMode(viewModel.isSelecting ? .inline : .large)
            .modifier(ConditionalSearchable(
                isActive: !viewModel.hasNoTransactions,
                text: $viewModel.searchText,
                prompt: "Search transactions..."
            ))
            // Hide the gear/＋ while selecting — the selection toolbar takes over.
            .appToolbar(showingAddItemView: $showingAddItemView, enabled: !viewModel.isSelecting)
            // Hide the floating tab bar while selecting so the action bar owns the bottom
            // and a stray tab tap can't navigate away and drop the selection.
            .toolbar(viewModel.isSelecting ? .hidden : .visible, for: .tabBar)
            .toolbar {
                if viewModel.isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Cancel")) { viewModel.exitSelection() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text(String(localized: "\(viewModel.selectedIDs.count) selected")).font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(viewModel.allVisibleSelected ? String(localized: "Deselect All") : String(localized: "Select All")) {
                            if viewModel.allVisibleSelected { viewModel.deselectAll() } else { viewModel.selectAllVisible() }
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.isSelecting)
            .safeAreaInset(edge: .bottom) {
                selectionActionBar
            }
            .sheet(isPresented: $showCategorySheet) {
                // Reuse the Add flow's category picker for visual consistency.
                BulkCategoryPickerSheet(repo: viewModel.repo) { category in
                    viewModel.bulkSetCategory(category)
                    showCategorySheet = false
                }
            }
            .sheet(isPresented: $showAmountSheet) {
                amountSheet
            }
            .sheet(isPresented: $showNoteSheet) {
                descriptionSheet
            }
            .overlay {
                if groupedFiltered.isEmpty && (!viewModel.searchText.isEmpty || viewModel.filters.isActive) {
                    ContentUnavailableView.search(text: viewModel.searchText)
                }
            }
            .onAppear { viewModel.load() }
        }
    }

    private func bulkButton(_ label: LocalizedStringKey, _ icon: String, tint: Color = .accentIndigo, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(tint)
        }
    }

    private func isRecurringDeletionPresented(for item: TransactionSnapshot) -> Binding<Bool> {
        Binding(
            get: { viewModel.pendingRecurrenceDeletion?.id == item.id },
            set: { if !$0 { viewModel.pendingRecurrenceDeletion = nil } }
        )
    }

    private var selectionActionBar: some View {
        Group {
            if viewModel.isSelecting {
                HStack(spacing: 4) {
                    bulkButton("Delete", "trash", tint: .red, role: .destructive) { viewModel.bulkDelete() }
                    bulkButton("Category", "tag") { showCategorySheet = true }
                    bulkButton("Amount", "eurosign.circle") { showAmountSheet = true }
                    bulkButton("Description", "text.alignleft") { showNoteSheet = true }
                }
                .disabled(viewModel.selectedIDs.isEmpty)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                // Floating glass bar, matching the app's GlassCard aesthetic.
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private var amountSheet: some View {
        AmountBulkEditSheet(
            count: viewModel.selectedIDs.count,
            onConfirm: { amount in
                viewModel.bulkSetAmount(Decimal(amount))
                showAmountSheet = false
            }
        )
    }

    private var descriptionSheet: some View {
        DescriptionBulkEditSheet(
            count: viewModel.selectedIDs.count,
            onConfirm: { description in
                viewModel.bulkSetNote(description)
                showNoteSheet = false
            }
        )
    }

    private var groupedFiltered: [(String, [TransactionSnapshot])] {
        guard let category = viewModel.effectiveCategory else { return viewModel.groupedItems }
        return viewModel.groupedItems.compactMap { (dateString, items) in
            let filtered = items.filter { $0.category == category }
            return filtered.isEmpty ? nil : (dateString, filtered)
        }
    }
}

private struct ConditionalSearchable: ViewModifier {
    let isActive: Bool
    @Binding var text: String
    let prompt: LocalizedStringKey

    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

/// Loads categories, then presents the Add flow's shared `CategoryPickerSheet`.
/// Fetching inside the sheet (not before presenting) guarantees the grid is populated.
private struct BulkCategoryPickerSheet: View {
    let repo: any ITransactionRepository
    let onApply: (CategorySnapshot) -> Void
    @State private var categories: [CategorySnapshot] = []
    @State private var selected: CategorySnapshot?

    var body: some View {
        CategoryPickerSheet(categories: categories, selectedCategory: $selected)
            .task {
                categories = (try? await repo.fetchCategories()) ?? []
            }
            .onChange(of: selected) { _, newValue in
                if let newValue { onApply(newValue) }
            }
    }
}

private struct AmountBulkEditSheet: View {
    let count: Int
    let onConfirm: (Double) -> Void
    @State private var amount: Double = 0.0
    @State private var currencyCode: String = "EUR"
    @State private var focusToken = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CurrencyAmountField(amount: $amount, currencyCode: $currencyCode, focusTrigger: focusToken)
                } footer: {
                    Text(String(localized: "Applies to \(count) transactions"))
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .navigationTitle(Text(String(localized: "New amount")))
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
            .presentationBackground { AppBackground() }
            .onAppear { focusToken += 1 }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Set")) {
                        onConfirm(amount)
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

private struct DescriptionBulkEditSheet: View {
    let count: Int
    let onConfirm: (String) -> Void
    @State private var description: String = ""
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...)
                        .focused($noteFocused)
                } footer: {
                    Text(String(localized: "Applies to \(count) transactions"))
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
            .navigationTitle(Text(String(localized: "Description")))
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
            .presentationBackground { AppBackground() }
            .onAppear { noteFocused = true }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Set")) {
                        onConfirm(description)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    SampleData.populateModelContext(container.mainContext)
    let vm = TransactionListViewModel(repo: TransactionActor.make(container))
    return ActivityView(showingAddItemView: .constant(false))
        .environment(vm)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
