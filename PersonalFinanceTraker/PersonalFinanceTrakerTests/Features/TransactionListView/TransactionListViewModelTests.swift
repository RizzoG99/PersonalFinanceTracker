import Testing
import Foundation
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
}
