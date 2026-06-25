import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct CategoryBreakdownViewModelTests {

    @Test @MainActor func loadPopulatesTransactions() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -50, note: "", category: "Food"),
            TransactionModel(timestamp: Date(), amount: 1000, note: "", category: "Salary"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        #expect(vm.transactions.count == 2)
        #expect(vm.loadError == nil)
    }

    @Test @MainActor func loadSetsErrorOnRepositoryFailure() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.shouldFail = true
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        #expect(vm.loadError != nil)
    }

    @Test @MainActor func pieChartDataFiltersToExpensesOnly() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -60, note: "", category: "Food"),
            TransactionModel(timestamp: Date(), amount: -40, note: "", category: "Transport"),
            TransactionModel(timestamp: Date(), amount: 1000, note: "", category: "Salary"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        vm.selectedTimePeriod = .week
        vm.selectedPieChartType = .expenses
        #expect(vm.pieChartData.count == 2)
        #expect(vm.pieChartData.allSatisfy { $0.category != "Salary" })
    }

    @Test @MainActor func pieChartDataFiltersToIncomeOnly() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -60, note: "", category: "Food"),
            TransactionModel(timestamp: Date(), amount: 1000, note: "", category: "Salary"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        vm.selectedTimePeriod = .week
        vm.selectedPieChartType = .income
        #expect(vm.pieChartData.allSatisfy { $0.category != "Food" })
        #expect(vm.pieChartData.contains { $0.category == "Salary" })
    }

    @Test @MainActor func summaryStatsTotalAndCountAreCorrect() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.transactions = [
            TransactionModel(timestamp: Date(), amount: -60, note: "", category: "Food"),
            TransactionModel(timestamp: Date(), amount: -40, note: "", category: "Transport"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        vm.selectedTimePeriod = .week
        vm.selectedPieChartType = .expenses
        #expect(vm.summaryStats.totalAmount == 100)
        #expect(vm.summaryStats.categoryCount == 2)
    }
}
