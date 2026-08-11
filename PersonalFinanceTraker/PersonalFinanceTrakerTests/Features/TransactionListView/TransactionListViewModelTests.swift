import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct TransactionListViewModelTests {

    @MainActor
    private func loadedVM(_ repo: MockTransactionRepository) async -> TransactionListViewModel {
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        return vm
    }

    @MainActor
    private func makeLoadedVM() async -> TransactionListViewModel {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [
            .test(amount: -50, note: "Coffee", category: "Food"),
            .test(amount: -30, note: "Tea", category: "Beverages"),
            .test(amount: -20, note: "Lunch", category: "Food"),
            .test(amount: 1000, note: "Salary", category: "Income"),
            .test(amount: -15, note: "Snack", category: "Food"),
        ]
        repo.stubbedCategories = [
            .test(name: "Food"),
            .test(name: "Beverages"),
            .test(name: "Income"),
        ]
        let ruleId = UUID()
        repo.stubbedRecurrenceRules = [
            .test(id: ruleId, startDate: .now, amount: -100, category: "Housing")
        ]
        // Add a recurring transaction
        repo.stubbedTransactions.append(.test(amount: -100, note: "Recurring", category: "Housing", recurrenceRuleId: ruleId))
        return await loadedVM(repo)
    }

    @MainActor
    private func makeRealRepoVM() async -> (vm: TransactionListViewModel, foodCat: CategorySnapshot, newCat: CategorySnapshot, expenseId: PersistentIdentifier, incomeId: PersistentIdentifier) {
        // Create in-memory container with all schemas
        let schema = Schema([TransactionModel.self, CategoryModel.self, GoalModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let actor = TransactionActor(modelContainer: container)

        // Create categories
        let foodCatInput = CategoryInput(name: "Food", systemImage: "fork.knife", type: "expense", colorToken: "categoryRed", monthlyBudget: nil, currencyCode: "EUR")
        try! await actor.addCategory(foodCatInput)
        let newCatInput = CategoryInput(name: "NewCategory", systemImage: "tag", type: "expense", colorToken: "categoryBlue", monthlyBudget: nil, currencyCode: "EUR")
        try! await actor.addCategory(newCatInput)

        // Fetch categories to get snapshots
        let categories = try! await actor.fetchCategories()
        let foodCat = categories.first { $0.name == "Food" }!
        let newCat = categories.first { $0.name == "NewCategory" }!

        // Insert transactions: one expense, one income
        let ctx = ModelContext(container)
        let expenseModel = TransactionModel(timestamp: Date(), amount: -50, note: "Coffee", category: "Food")
        let incomeModel = TransactionModel(timestamp: Date(), amount: 1000, note: "Salary", category: "Income")
        ctx.insert(expenseModel)
        ctx.insert(incomeModel)
        try! ctx.save()

        // Get transaction IDs for later assertion
        let expenseId = expenseModel.persistentModelID
        let incomeId = incomeModel.persistentModelID

        // Create VM with real actor as repo
        let vm = TransactionListViewModel(repo: actor)
        vm.load()
        await vm.loadTask?.value

        return (vm, foodCat, newCat, expenseId, incomeId)
    }

    @Test @MainActor func testClearSearch() async throws {
        let mockRepo = MockTransactionRepository()
        let viewModel = TransactionListViewModel(repo: mockRepo)
        viewModel.searchText = "Coffee"
        viewModel.clearSearch()
        #expect(viewModel.searchText == "")
    }

    @Test @MainActor func loadFetchesAllTransactions() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: -50, note: "Coffee", category: "Food"),
            .test(amount: 1000, note: "Salary", category: "Income"),
        ]
        let vm = await loadedVM(mockRepo)
        #expect(vm.transactions.count == 2)
    }

    @Test @MainActor func addTransactionCallsRepoAndReloads() async throws {
        let mockRepo = MockTransactionRepository()
        let vm = await loadedVM(mockRepo)

        let input = TransactionInput(timestamp: Date(), amount: -30, note: "Coffee", category: "Food", currencyCode: "EUR")
        await vm.add(input)
        await vm.loadTask?.value

        #expect(mockRepo.addCalledCount == 1)
        #expect(mockRepo.fetchAllCallCount >= 2) // initial load + reload after add
    }

    @Test @MainActor func totalFilteredIncomeSumsPositiveAmounts() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: 1000, note: "Salary", category: "Income"),
            .test(amount: 500, note: "Freelance", category: "Income"),
            .test(amount: -200, note: "Food", category: "Food"),
        ]
        let vm = await loadedVM(mockRepo)
        #expect(vm.totalFilteredIncome == 1500)
    }

    @Test @MainActor func totalFilteredExpensesReturnsPositiveValue() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: -200, note: "Food", category: "Food"),
            .test(amount: -50, note: "Coffee", category: "Food"),
            .test(amount: 1000, note: "Salary", category: "Income"),
        ]
        let vm = await loadedVM(mockRepo)
        #expect(vm.totalFilteredExpenses == 250)
    }

    @Test @MainActor func searchTextFiltersTransactionsByNote() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: -50, note: "Coffee", category: "Food"),
            .test(amount: -20, note: "Bus ticket", category: "Transport"),
        ]
        let vm = await loadedVM(mockRepo)
        vm.searchText = "Coffee"
        await vm.searchDebounceTask?.value
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.note == "Coffee")
    }

    // MARK: - Deferred delete

    @Test @MainActor func deleteItemsFromSectionSetsUndoBannerAndDoesNotCallRepo() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionSnapshot.test(amount: -10, note: "A", category: "Food")
        let t2 = TransactionSnapshot.test(amount: -20, note: "B", category: "Food")
        mockRepo.stubbedTransactions = [t1, t2]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1, t2], offsets: IndexSet([0]))

        #expect(vm.showUndoBanner == true)
        #expect(vm.pendingDeletion.count == 1)
        #expect(vm.pendingDeletion.first?.id == t1.id)
        #expect(vm.transactions.count == 1) // optimistically removed
        #expect(mockRepo.deleteCalledCount == 0) // repo not touched yet
    }

    @Test @MainActor func commitPendingDeletionCallsRepoAndClearsBanner() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionSnapshot.test(amount: -10, note: "A", category: "Food")
        mockRepo.stubbedTransactions = [t1]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))
        await vm.commitPendingDeletion()

        #expect(mockRepo.deleteCalledCount == 1)
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.showUndoBanner == false)
        #expect(vm.deleteProgress == 0.0)
    }

    @Test @MainActor func undoDeleteRestoresTransactionsAndClearsBanner() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionSnapshot.test(amount: -10, note: "A", category: "Food")
        mockRepo.stubbedTransactions = [t1]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))
        #expect(vm.transactions.count == 0) // optimistically removed

        vm.undoDelete()
        await vm.loadTask?.value

        #expect(vm.showUndoBanner == false)
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.transactions.count == 1) // restored from repo
        #expect(mockRepo.deleteCalledCount == 0) // repo was never touched
        #expect(vm.deleteProgress == 0.0)
    }

    @Test @MainActor func mergeDeleteWhilePendingPoolsItemsAndResetsBanner() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionSnapshot.test(amount: -10, note: "A", category: "Food")
        let t2 = TransactionSnapshot.test(amount: -20, note: "B", category: "Food")
        mockRepo.stubbedTransactions = [t1, t2]
        let vm = await loadedVM(mockRepo)

        // First delete — starts timer
        vm.deleteItemsFromSection(dayItems: [t1, t2], offsets: IndexSet([0]))
        #expect(vm.pendingDeletion.count == 1)
        #expect(vm.deleteProgress == 0.0)
        #expect(mockRepo.deleteCalledCount == 0)

        // Second delete while timer is running — must merge, not commit
        vm.deleteItemsFromSection(dayItems: [t2], offsets: IndexSet([0]))
        #expect(mockRepo.deleteCalledCount == 0)   // repo still untouched
        #expect(vm.pendingDeletion.count == 2)      // both items pooled
        #expect(vm.deleteProgress == 0.0)           // timer reset
        #expect(vm.showUndoBanner == true)
    }

    @Test @MainActor func deleteBatchGroupsAllItemsUnderOnePendingSet() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionSnapshot.test(amount: -10, note: "A", category: "Food")
        let t2 = TransactionSnapshot.test(amount: -20, note: "B", category: "Food")
        let t3 = TransactionSnapshot.test(amount: -30, note: "C", category: "Food")
        mockRepo.stubbedTransactions = [t1, t2, t3]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1, t2, t3], offsets: IndexSet([0, 1, 2]))

        #expect(vm.pendingDeletion.count == 3)
        #expect(vm.transactions.isEmpty)
        #expect(mockRepo.deleteCalledCount == 0)
    }

    // MARK: - Swiping a recurring occurrence

    @Test @MainActor func deletingSingleRecurringItemPromptsInsteadOfScheduling() async throws {
        let mockRepo = MockTransactionRepository()
        let ruleId = UUID()
        let t1 = TransactionSnapshot.test(amount: -10, note: "Rent", category: "Housing", recurrenceRuleId: ruleId)
        mockRepo.stubbedTransactions = [t1]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))

        #expect(vm.pendingRecurrenceDeletion?.id == t1.id)
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.showUndoBanner == false)
        #expect(vm.transactions.count == 1) // not optimistically removed — awaiting scope choice
        #expect(mockRepo.deleteCalledCount == 0)
    }

    @Test @MainActor func applyRecurrenceDeletionScopeThisOnlyDeletesJustThatRow() async throws {
        let mockRepo = MockTransactionRepository()
        let ruleId = UUID()
        let t1 = TransactionSnapshot.test(amount: -10, note: "Rent", category: "Housing", recurrenceRuleId: ruleId)
        mockRepo.stubbedTransactions = [t1]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))
        vm.applyRecurrenceDeletionScope(.thisOnly)
        try await Task.sleep(for: .milliseconds(50))

        #expect(mockRepo.deleteCalledCount == 1)
        #expect(mockRepo.closeRecurrenceRuleCalls.isEmpty)
        #expect(mockRepo.deleteOccurrencesCalls.isEmpty)
        #expect(vm.pendingRecurrenceDeletion == nil)
    }

    @Test @MainActor func applyRecurrenceDeletionScopeThisAndFutureClosesRuleAndDeletesOccurrences() async throws {
        let mockRepo = MockTransactionRepository()
        let ruleId = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = TransactionSnapshot.test(timestamp: timestamp, amount: -10, note: "Rent", category: "Housing", recurrenceRuleId: ruleId)
        mockRepo.stubbedTransactions = [t1]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))
        vm.applyRecurrenceDeletionScope(.thisAndFuture)
        try await Task.sleep(for: .milliseconds(50))

        #expect(mockRepo.deleteCalledCount == 0) // series closed, not the single-row delete path
        #expect(mockRepo.closeRecurrenceRuleCalls.count == 1)
        #expect(mockRepo.closeRecurrenceRuleCalls.first?.id == ruleId)
        let expectedDayBefore = Calendar.current.date(byAdding: .day, value: -1, to: timestamp)
        #expect(mockRepo.closeRecurrenceRuleCalls.first?.endDate == expectedDayBefore)
        #expect(mockRepo.deleteOccurrencesCalls.count == 1)
        #expect(mockRepo.deleteOccurrencesCalls.first?.recurrenceRuleId == ruleId)
        #expect(vm.pendingRecurrenceDeletion == nil)
    }

    @Test @MainActor func deletingNonRecurringItemStillUsesUndoBanner() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionSnapshot.test(amount: -10, note: "Coffee", category: "Food")
        mockRepo.stubbedTransactions = [t1]
        let vm = await loadedVM(mockRepo)

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))

        #expect(vm.pendingRecurrenceDeletion == nil)
        #expect(vm.showUndoBanner == true)
        #expect(vm.pendingDeletion.count == 1)
    }

    // MARK: - Totals match the list

    @Test @MainActor func totalsIncludeAllListedTransactionsRegardlessOfAge() async throws {
        let mockRepo = MockTransactionRepository()
        let pastDate = Calendar.current.date(byAdding: .day, value: -100, to: .now) ?? .now

        mockRepo.stubbedTransactions = [
            .test(timestamp: .now, amount: 1000, note: "Recent Salary", category: "Income"),
            .test(timestamp: pastDate, amount: 500, note: "Old Income", category: "Income"),
            .test(timestamp: pastDate, amount: -300, note: "Old Expense", category: "Food"),
        ]
        let vm = await loadedVM(mockRepo)
        vm.selectedTimePeriod = .week

        // Activity totals mirror the visible list — selectedTimePeriod only drives the chart
        #expect(vm.totalFilteredIncome == 1500)
        #expect(vm.totalFilteredExpenses == 300)
    }

    // MARK: - Category Filter

    @Test @MainActor func totalsScopedToSelectedCategory() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: -200, note: "Espresso", category: "Coffee"),
            .test(amount: -300, note: "Groceries", category: "Food"),
            .test(amount: 1000, note: "Salary", category: "Income"),
        ]
        let vm = await loadedVM(mockRepo)

        vm.selectedCategory = "Coffee"
        #expect(vm.totalFilteredExpenses == 200)
        #expect(vm.totalFilteredIncome == 0)

        vm.selectedCategory = nil
        #expect(vm.totalFilteredExpenses == 500)
        #expect(vm.totalFilteredIncome == 1000)
    }

    @Test @MainActor func staleCategorySelectionIsIgnored() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: -200, note: "Espresso", category: "Coffee"),
            .test(amount: -300, note: "Groceries", category: "Food"),
        ]
        let vm = await loadedVM(mockRepo)

        vm.selectedCategory = "Coffee"
        // Search narrows the data so "Coffee" no longer exists — selection must not zero everything out
        vm.searchText = "Groceries"
        await vm.searchDebounceTask?.value
        #expect(vm.effectiveCategory == nil)
        #expect(vm.totalFilteredExpenses == 300)
    }

    @Test @MainActor func filterCategoriesSortedByFrequencyThenName() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            .test(amount: -1, note: "a", category: "Food"),
            .test(amount: -1, note: "b", category: "Food"),
            .test(amount: -1, note: "c", category: "Coffee"),
            .test(amount: -1, note: "d", category: "Bar"),
        ]
        let vm = await loadedVM(mockRepo)

        #expect(vm.filterCategories == ["Food", "Bar", "Coffee"])
    }

    @Test @MainActor func savedSelectionsPrefillOnlyValidCategories() {
        let vm = TransactionListViewModel(repo: MockTransactionRepository())
        let food = CategorySnapshot.test(name: "Food")
        vm.availableCategories = [food]
        vm.csvCategories = ["🍕 Food", "Ghost"]
        vm.importProfileStore = ImportProfileStore(
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        )

        // Simulate a stored profile: one valid selection, one pointing at a deleted category
        let sig = ImportProfileStore.signature(headers: ["A"], delimiter: ",")
        vm.importProfileStore.save(
            ImportProfile(
                mapping: ColumnMapping(),
                categorySelections: [
                    "🍕 Food": food.id.uuidString,
                    "Ghost": UUID().uuidString,
                ]
            ),
            for: sig
        )
        // Feed the saved selections through the same path applyImportProfileIfAvailable uses
        vm.setSavedCategorySelectionsForTesting(
            vm.importProfileStore.profile(for: sig)?.categorySelections
        )

        vm.applySavedCategorySelections()

        #expect(vm.categoryResolutionSelections["🍕 Food"] == food.id.uuidString)
        #expect(vm.categoryResolutionSelections["Ghost"] == nil)
    }

    // MARK: - Multi-select

    @Test @MainActor func toggleSelectionAddsAndRemoves() async {
        let vm = await makeLoadedVM()
        let id = vm.filteredItems[0].id
        vm.toggleSelection(id)
        #expect(vm.selectedIDs.contains(id))
        vm.toggleSelection(id)
        #expect(!vm.selectedIDs.contains(id))
    }

    @Test @MainActor func selectAllVisibleSelectsOnlyFiltered() async {
        let vm = await makeLoadedVM()
        vm.searchText = "coffee"
        try? await vm.searchDebounceTask?.value
        vm.selectAllVisible()
        #expect(vm.selectedIDs == Set(vm.filteredItems.map(\.id)))
        #expect(vm.selectedIDs.count < vm.transactions.count)
    }

    @Test @MainActor func filteringOutSelectedRowDropsIt() async {
        let vm = await makeLoadedVM()
        let id = vm.filteredItems.first { $0.note.localizedCaseInsensitiveContains("coffee") == false }!.id
        vm.toggleSelection(id)
        vm.searchText = "coffee"
        try? await vm.searchDebounceTask?.value
        #expect(!vm.selectedIDs.contains(id))
    }

    @Test @MainActor func exitSelectionClearsState() async {
        let vm = await makeLoadedVM()
        vm.isSelecting = true
        vm.toggleSelection(vm.filteredItems[0].id)
        vm.exitSelection()
        #expect(!vm.isSelecting)
        #expect(vm.selectedIDs.isEmpty)
    }

    // MARK: - Generalized undo (edits and deletes)

    @Test @MainActor func armUndoForEditDoesNotDeleteOnTimeout() async {
        let vm = await makeLoadedVM()
        let before = vm.transactions.count
        var reverted = false
        await vm.armUndo(message: "2 transactions updated") { reverted = true }
        #expect(vm.showUndoBanner)
        #expect(vm.pendingDeletion.isEmpty)          // edit path never populates pendingDeletion
        await vm.commitPending()                       // simulate timeout firing
        #expect(vm.transactions.count == before)      // Gap 2: nothing deleted
        #expect(!reverted)                             // commit is a no-op; revert only runs on undo
        #expect(!vm.showUndoBanner)
    }

    @Test @MainActor func undoForEditRunsRevert() async {
        let vm = await makeLoadedVM()
        var reverted = false
        await vm.armUndo(message: "x") { reverted = true }
        vm.undoPending()
        await vm.bulkEditTask?.value   // undo's revert Task, exposed via the shared handle
        #expect(reverted)
        #expect(!vm.showUndoBanner)
    }

    @Test @MainActor func singleDeleteStillCommits() async {   // regression
        let vm = await makeLoadedVM()
        let item = vm.filteredItems.first { $0.recurrenceRuleId == nil }!
        let before = vm.transactions.count
        vm.delete(item)
        await vm.commitPending()
        #expect(vm.transactions.count == before - 1)
        #expect(vm.pendingDeletion.isEmpty)
    }

    // Cross-kind flush: arming an edit while a delete is pending must FINALIZE the delete
    // (commit it), not abandon it. Without the flush the removed rows would reappear on
    // the next reload — the blocking leak this guards against.
    @Test @MainActor func armingEditFlushesPendingDelete() async {
        let vm = await makeLoadedVM()
        let item = vm.filteredItems.first { $0.recurrenceRuleId == nil }!
        vm.delete(item)                       // arm a delete: row removed, pendingDeletion=[item]
        #expect(vm.pendingDeletion.count == 1)
        await vm.armUndo(message: "edited") { }   // arming an edit flushes the pending delete
        let after = try! await vm.repo.fetchAll()
        #expect(!after.contains { $0.id == item.id })   // delete was committed, not leaked
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.showUndoBanner)                        // edit's banner now showing
    }

    // MARK: - Bulk mutations

    @Test @MainActor func bulkDeleteRemovesSelected() async {
        let vm = await makeLoadedVM()
        let targets = Array(vm.filteredItems.prefix(2))
        targets.forEach { vm.toggleSelection($0.id) }
        let before = vm.transactions.count
        vm.bulkDelete()
        #expect(!vm.isSelecting)
        await vm.commitPending()
        #expect(vm.transactions.count == before - 2)
    }

    @Test @MainActor func bulkSetCategoryRewritesOnlySelected() async {
        let (vm, foodCat, newCat, expenseId, _) = await makeRealRepoVM()
        // Select first (expense) transaction
        let target = vm.filteredItems.first { $0.id == expenseId }!
        let other = vm.filteredItems.first { $0.id != expenseId }!
        let otherCatBefore = other.category
        vm.toggleSelection(target.id)
        vm.bulkSetCategory(newCat)
        await vm.bulkEditTask?.value
        let after = try! await vm.repo.fetchAll()
        #expect(after.first { $0.id == target.id }!.category == newCat.name)
        #expect(after.first { $0.id == other.id }!.category == otherCatBefore)   // untouched
        #expect(vm.showUndoBanner)
    }

    @Test @MainActor func bulkSetCategoryFlipsTypeToMatchCategory() async {
        let (vm, foodCat, _, expenseId, incomeId) = await makeRealRepoVM()
        // Add an income-typed category alongside the expense-typed ones.
        try! await vm.repo.addCategory(CategoryInput(name: "Salary", systemImage: "banknote", type: TransactionType.income.rawValue, colorToken: "categoryGreen", monthlyBudget: nil, currencyCode: "EUR"))
        let salaryCat = (try! await vm.repo.fetchCategories()).first { $0.name == "Salary" }!

        // Income category applied to the -50 expense → flips to +50 income.
        vm.toggleSelection(expenseId)
        vm.bulkSetCategory(salaryCat)
        await vm.bulkEditTask?.value
        await vm.loadTask?.value
        var after = try! await vm.repo.fetchAll()
        #expect(after.first { $0.id == expenseId }!.amount == 50)
        #expect(after.first { $0.id == expenseId }!.category == "Salary")

        // Expense category applied to the +1000 income → flips to -1000 expense.
        vm.exitSelection()
        vm.toggleSelection(incomeId)
        vm.bulkSetCategory(foodCat)
        await vm.bulkEditTask?.value
        after = try! await vm.repo.fetchAll()
        #expect(after.first { $0.id == incomeId }!.amount == -1000)
        #expect(after.first { $0.id == incomeId }!.category == "Food")
    }

    @Test @MainActor func bulkSetAmountPreservesSign() async {
        let (vm, _, _, expenseId, incomeId) = await makeRealRepoVM()
        let expense = vm.filteredItems.first { $0.id == expenseId }!
        let income = vm.filteredItems.first { $0.id == incomeId }!
        vm.toggleSelection(expense.id); vm.toggleSelection(income.id)
        vm.bulkSetAmount(25)
        await vm.bulkEditTask?.value
        let after = try! await vm.repo.fetchAll()
        #expect(after.first { $0.id == expense.id }!.amount == -25)   // stays negative
        #expect(after.first { $0.id == income.id }!.amount == 25)     // stays positive
    }

    @Test @MainActor func bulkSetNoteOverwritesSelected() async {
        let (vm, _, _, expenseId, _) = await makeRealRepoVM()
        let target = vm.filteredItems.first { $0.id == expenseId }!
        vm.toggleSelection(target.id)
        vm.bulkSetNote("reconciled")
        await vm.bulkEditTask?.value
        let after = try! await vm.repo.fetchAll()
        #expect(after.first { $0.id == target.id }!.note == "reconciled")
    }

    @Test @MainActor func bulkEditUndoRestoresPriorValues() async {
        let (vm, _, _, expenseId, _) = await makeRealRepoVM()
        let target = vm.filteredItems.first { $0.id == expenseId }!
        let priorNote = target.note
        vm.toggleSelection(target.id)
        vm.bulkSetNote("changed")
        await vm.bulkEditTask?.value
        vm.undoPending()
        await vm.bulkEditTask?.value
        let after = try! await vm.repo.fetchAll()
        #expect(after.first { $0.id == target.id }!.note == priorNote)
    }

    @Test @MainActor func bulkDeleteRecurringDoesNotCloseRule() async {
        let vm = await makeLoadedVM()
        guard let recurring = vm.filteredItems.first(where: { $0.recurrenceRuleId != nil }) else { return }
        let ruleId = recurring.recurrenceRuleId!
        vm.toggleSelection(recurring.id)
        vm.bulkDelete()
        await vm.commitPending()
        // The rule must still exist (bulk delete is this-only).
        let rules = try! await vm.repo.fetchAllRecurrenceRules()
        #expect(rules.contains { $0.id == ruleId })
    }

    @Test @MainActor func bulkOpsNoopOnEmptySelection() async {
        let vm = await makeLoadedVM()
        let before = vm.transactions.count
        vm.bulkDelete()
        vm.bulkSetNote("x")
        #expect(vm.transactions.count == before)
        #expect(!vm.showUndoBanner)
    }
}
