import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct CategoryBreakdownViewModelTests {

    private func makeSnapshot(amount: Decimal, category: String) -> TransactionSnapshot {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: TransactionModel.self, configurations: config)
        let ctx = ModelContext(container)
        let model = TransactionModel(timestamp: Date(), amount: amount, note: "", category: category)
        ctx.insert(model)
        try! ctx.save()
        return TransactionSnapshot(model)
    }

    // load() fires an async Task; spin until it lands (bounded so a bug fails instead of hanging).
    @MainActor
    private func awaitLoad(until done: @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if done() { return }
            await Task.yield()
        }
    }

    @Test @MainActor func loadPopulatesTransactions() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            makeSnapshot(amount: -50, category: "Food"),
            makeSnapshot(amount: 1000, category: "Salary"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        await awaitLoad { !vm.transactions.isEmpty }
        #expect(vm.transactions.count == 2)
        #expect(vm.loadError == nil)
    }

    @Test @MainActor func loadSetsErrorOnRepositoryFailure() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.shouldThrow = true
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        await awaitLoad { vm.loadError != nil }
        #expect(vm.loadError != nil)
    }

    @Test @MainActor func pieChartDataFiltersToExpensesOnly() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            makeSnapshot(amount: -60, category: "Food"),
            makeSnapshot(amount: -40, category: "Transport"),
            makeSnapshot(amount: 1000, category: "Salary"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        await awaitLoad { !vm.transactions.isEmpty }
        vm.selectedTimePeriod = .week
        vm.selectedPieChartType = .expenses
        #expect(vm.pieChartData.count == 2)
        #expect(vm.pieChartData.allSatisfy { $0.category != "Salary" })
    }

    @Test @MainActor func pieChartDataFiltersToIncomeOnly() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            makeSnapshot(amount: -60, category: "Food"),
            makeSnapshot(amount: 1000, category: "Salary"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        await awaitLoad { !vm.transactions.isEmpty }
        vm.selectedTimePeriod = .week
        vm.selectedPieChartType = .income
        #expect(vm.pieChartData.allSatisfy { $0.category != "Food" })
        #expect(vm.pieChartData.contains { $0.category == "Salary" })
    }

    @Test @MainActor func summaryStatsTotalAndCountAreCorrect() async throws {
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedTransactions = [
            makeSnapshot(amount: -60, category: "Food"),
            makeSnapshot(amount: -40, category: "Transport"),
        ]
        let vm = CategoryBreakdownViewModel(repo: mockRepo)
        vm.load()
        await awaitLoad { !vm.transactions.isEmpty }
        vm.selectedTimePeriod = .week
        vm.selectedPieChartType = .expenses
        #expect(vm.summaryStats.totalAmount == 100)
        #expect(vm.summaryStats.categoryCount == 2)
    }
}
