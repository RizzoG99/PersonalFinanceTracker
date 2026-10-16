//
//  ActivityView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct ActivityView: View {
    @Environment(TransactionListViewModel.self) private var viewModel: TransactionListViewModel
    @Binding var showingAddItemView: Bool
    var onScanned: ((ReceiptScan) -> Void)? = nil
    @Binding var showingTravelsView: Bool

    @State private var showCategorySheet = false
    @State private var showAmountSheet = false
    @State private var showNoteSheet = false
    @State private var selectedTravel: TravelSummary? = nil
    @State private var showTravelPicker = false
    @State private var pendingTravelDeletion: TravelSummary? = nil
    /// Travel whose "Add expense" was tapped. The Add sheet is opened from the *dismissal* of
    /// the sheet that asked for it — presenting one sheet while another is still going down
    /// drops the presentation.
    @State private var pendingAddExpenseTravelId: UUID? = nil

    var body: some View {
        let measurement = PerformanceAuditRecorder.begin("Activity.view.body")
        defer { PerformanceAuditRecorder.end(measurement) }
        @Bindable var viewModel = viewModel
        let activityPage = viewModel.activityPage
        return NavigationStack {
            List {
                ActivitySummarySection(showingAddItemView: $showingAddItemView)

                ForEach(activityPage.groups, id: \.0) { dateString, dayItems in
                    ActivityDateSection(
                        dateString: dateString,
                        rows: dayItems,
                        selectedTravel: $selectedTravel,
                        pendingTravelDeletion: $pendingTravelDeletion
                    )
                }

                if activityPage.hasMoreRows {
                    ActivityLoadMoreSection(remainingRowCount: activityPage.remainingRowCount)
                }

            }
            .onAppear {
                PerformanceAuditRecorder.event(
                    "Activity.list.appeared",
                    metadata: "transactions=\(viewModel.transactions.count) groups=\(activityPage.groups.count) rows=\(activityPage.groups.reduce(0) { $0 + $1.1.count })"
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            .appToolbar(showingAddItemView: $showingAddItemView, enabled: !viewModel.isSelecting, onScanned: onScanned)
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
                } else {
                    // Recurring used to share an overflow menu with this; it moved to the Plan
                    // tab (#187), so Travels is the only list left and gets a direct button.
                    // Creating a travel still lives on the plus inside that list and in the add
                    // transaction form, never here.
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Travels", systemImage: "airplane") { showingTravelsView = true }
                    }
                }
            }
            .sheet(isPresented: $showingTravelsView, onDismiss: flushPendingAddExpense) {
                NavigationStack {
                    TravelsView(onAddExpense: { travelId in
                        pendingAddExpenseTravelId = travelId
                        showingTravelsView = false
                    })
                }
                .presentationBackground { AppBackground() }
            }
            .appBackground()
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
            // The same Travels list the ⋯ menu opens, in moving mode. It used to be a
            // second, thinner sheet listing the same trips.
            .sheet(isPresented: $showTravelPicker) {
                NavigationStack {
                    TravelsView(
                        mode: .movingSelection,
                        // Read here, where the selection is still intact and the value is
                        // known before the sheet sizes itself.
                        selectionHasTravel: viewModel.selectionHasTravel
                    )
                }
                .presentationBackground { AppBackground() }
            }
            .sheet(item: $selectedTravel, onDismiss: flushPendingAddExpense) { summary in
                TravelDetailSheet(
                    travel: summary,
                    members: viewModel.members(of: summary),
                    onAddExpense: {
                        pendingAddExpenseTravelId = summary.id
                        selectedTravel = nil
                    },
                    onSelect: { item in
                        selectedTravel = nil
                        viewModel.transactionToEdit = item
                    },
                    onRemoveMember: { viewModel.removeFromTravel($0) },
                    onRename: { name, symbolName in
                        viewModel.renameTravel(id: summary.id, name: name, symbolName: symbolName)
                        selectedTravel = nil
                    },
                    onDelete: { viewModel.deleteTravel(id: summary.id) }
                )
                .presentationBackground { AppBackground() }
            }
            .overlay {
                if activityPage.groups.isEmpty && (!viewModel.searchText.isEmpty || viewModel.filters.isActive) {
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
    private var selectionActionBar: some View {
        Group {
            if viewModel.isSelecting {
                HStack(spacing: 4) {
                    bulkButton("Delete", "trash", tint: .red, role: .destructive) { viewModel.bulkDelete() }
                    bulkButton("Category", "tag") { showCategorySheet = true }
                    bulkButton("Amount", "eurosign.circle") { showAmountSheet = true }
                    bulkButton("Description", "text.alignleft") { showNoteSheet = true }
                    bulkButton("Travel", "airplane") { showTravelPicker = true }
                }
                .disabled(viewModel.selectedIDs.isEmpty)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                // Floating glass bar, matching the app's GlassCard aesthetic. A subtle dark
                // tint keeps scrolled list content reading as *behind* the bar rather than
                // bleeding through it.
                .glassEffect(.regular.tint(Color.bg0.opacity(0.55)), in: .rect(cornerRadius: 24))
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
    /// Called from the dismissal of whichever sheet asked for it; the shell then opens the
    /// Add form already tagged with the travel.
    private func flushPendingAddExpense() {
        guard let travelId = pendingAddExpenseTravelId else { return }
        pendingAddExpenseTravelId = nil
        viewModel.addExpenseTravelId = travelId
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
// Internal rather than private: the iPad ledger table reuses these three verbatim.
struct BulkCategoryPickerSheet: View {
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

struct AmountBulkEditSheet: View {
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

struct DescriptionBulkEditSheet: View {
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
    let base: ActivityView = ActivityView(
        showingAddItemView: .constant(false),
        showingTravelsView: .constant(false)
    )
    return base
        .environment(vm)
        .environment(ProfileViewModel())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
