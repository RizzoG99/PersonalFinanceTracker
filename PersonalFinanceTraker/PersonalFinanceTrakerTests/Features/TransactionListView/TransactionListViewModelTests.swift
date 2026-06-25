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
}
