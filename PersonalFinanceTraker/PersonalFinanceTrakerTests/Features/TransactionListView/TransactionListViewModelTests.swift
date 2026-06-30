import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct TransactionListViewModelTests {

    @Test @MainActor func testClearSearch() async throws {
        let mockRepo = MockTransactionRepository()
        let viewModel = TransactionListViewModel(repo: mockRepo)
        viewModel.searchText = "Coffee"
        viewModel.clearSearch()
        #expect(viewModel.searchText == "")
    }

    @Test @MainActor func loadFetchesAllTransactions() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -50, note: "Coffee", category: "Food"),
            TransactionModel(timestamp: Date(), amount: 1000, note: "Salary", category: "Income"),
        ]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()
        #expect(vm.transactions.count == 2)
    }

    @Test @MainActor func addTransactionCallsRepoAndReloads() async throws {
        let mockRepo = MockTransactionRepository()
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.add(date: Date(), amount: -30, note: "Coffee", category: "Food")
        #expect(mockRepo.addCalledCount == 1)
        #expect(vm.transactions.count == 1)
    }

    @Test @MainActor func totalFilteredIncomeSumsPositiveAmounts() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: 1000, note: "Salary", category: "Income"),
            TransactionModel(timestamp: Date(), amount: 500, note: "Freelance", category: "Income"),
            TransactionModel(timestamp: Date(), amount: -200, note: "Food", category: "Food"),
        ]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()
        #expect(vm.totalFilteredIncome == 1500)
    }

    @Test @MainActor func totalFilteredExpensesReturnsPositiveValue() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -200, note: "Food", category: "Food"),
            TransactionModel(timestamp: Date(), amount: -50, note: "Coffee", category: "Food"),
            TransactionModel(timestamp: Date(), amount: 1000, note: "Salary", category: "Income"),
        ]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()
        #expect(vm.totalFilteredExpenses == 250)
    }

    @Test @MainActor func exportCSVContainsHeaderAndTransactionData() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -50, note: "Lunch", category: "Food"),
        ]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()
        let csv = vm.exportCSV()
        #expect(csv.hasPrefix("Date,Amount,Currency,Category,Note,Type"))
        #expect(csv.contains("Food"))
        #expect(csv.contains("Lunch"))
    }

    @Test @MainActor func searchTextFiltersTransactionsByNote() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -50, note: "Coffee", category: "Food"),
            TransactionModel(timestamp: Date(), amount: -20, note: "Bus ticket", category: "Transport"),
        ]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()
        vm.searchText = "Coffee"
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.note == "Coffee")
    }

    @Test @MainActor func deleteCallsRepoDelete() async throws {
        let tx = TransactionModel(timestamp: Date(), amount: -50, note: "Lunch", category: "Food")
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [tx]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()
        vm.deleteItemsFromSection(dayItems: [tx], offsets: IndexSet([0]))
        #expect(mockRepo.deleteCalledCount == 1)
    }

    // MARK: - Deferred delete

    @Test @MainActor func deleteItemsFromSectionSetsUndoBannerAndDoesNotCallRepo() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionModel(timestamp: Date(), amount: -10, note: "A", category: "Food")
        let t2 = TransactionModel(timestamp: Date(), amount: -20, note: "B", category: "Food")
        mockRepo.transactions = [t1, t2]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()

        vm.deleteItemsFromSection(dayItems: [t1, t2], offsets: IndexSet([0]))

        #expect(vm.showUndoBanner == true)
        #expect(vm.pendingDeletion.count == 1)
        #expect(vm.pendingDeletion.first?.id == t1.id)
        #expect(vm.transactions.count == 1) // optimistically removed
        #expect(mockRepo.deleteCalledCount == 0) // repo not touched yet
    }

    @Test @MainActor func commitPendingDeletionCallsRepoAndClearsBanner() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionModel(timestamp: Date(), amount: -10, note: "A", category: "Food")
        mockRepo.transactions = [t1]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))
        vm.commitPendingDeletion()

        #expect(mockRepo.deleteCalledCount == 1)
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.showUndoBanner == false)
    }

    @Test @MainActor func undoDeleteRestoresTransactionsAndClearsBanner() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionModel(timestamp: Date(), amount: -10, note: "A", category: "Food")
        mockRepo.transactions = [t1]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()

        vm.deleteItemsFromSection(dayItems: [t1], offsets: IndexSet([0]))
        #expect(vm.transactions.count == 0) // optimistically removed

        vm.undoDelete()

        #expect(vm.showUndoBanner == false)
        #expect(vm.pendingDeletion.isEmpty)
        #expect(vm.transactions.count == 1) // restored from repo
        #expect(mockRepo.deleteCalledCount == 0) // repo was never touched
    }

    @Test @MainActor func newDeleteWhilePendingCommitsPreviousBatchFirst() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionModel(timestamp: Date(), amount: -10, note: "A", category: "Food")
        let t2 = TransactionModel(timestamp: Date(), amount: -20, note: "B", category: "Food")
        mockRepo.transactions = [t1, t2]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()

        // Delete t1 — starts timer
        vm.deleteItemsFromSection(dayItems: [t1, t2], offsets: IndexSet([0]))
        #expect(mockRepo.deleteCalledCount == 0)

        // Delete t2 while timer is running — must commit t1 first
        vm.deleteItemsFromSection(dayItems: [t2], offsets: IndexSet([0]))
        #expect(mockRepo.deleteCalledCount == 1) // t1 committed
        #expect(vm.pendingDeletion.count == 1)   // t2 now pending
        #expect(vm.pendingDeletion.first?.id == t2.id)
    }

    @Test @MainActor func deleteBatchGroupsAllItemsUnderOnePendingSet() async throws {
        let mockRepo = MockTransactionRepository()
        let t1 = TransactionModel(timestamp: Date(), amount: -10, note: "A", category: "Food")
        let t2 = TransactionModel(timestamp: Date(), amount: -20, note: "B", category: "Food")
        let t3 = TransactionModel(timestamp: Date(), amount: -30, note: "C", category: "Food")
        mockRepo.transactions = [t1, t2, t3]
        let vm = TransactionListViewModel(repo: mockRepo)
        vm.load()

        vm.deleteItemsFromSection(dayItems: [t1, t2, t3], offsets: IndexSet([0, 1, 2]))

        #expect(vm.pendingDeletion.count == 3)
        #expect(vm.transactions.isEmpty)
        #expect(mockRepo.deleteCalledCount == 0)
    }
}
