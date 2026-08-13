import Testing
import Foundation
@testable import PersonalFinanceTraker

@MainActor
@Suite(.serialized)
struct CompassViewModelTests {

    private func makeVM(transactions: [TransactionSnapshot]) async -> CompassViewModel {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = transactions
        let vm = CompassViewModel(repo: repo)
        // Awaits the load directly rather than sleeping past it. `load()` is
        // fire-and-forget, so the previous 100ms sleep was a guess that came up
        // short when the full suite ran and the load was scheduled late.
        await vm.reloadData()
        return vm
    }

    private func makeIncome(amount: Decimal, monthsAgo: Int = 0) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return .test(timestamp: date, amount: amount, category: "Salary")
    }

    private func makeExpense(amount: Decimal, category: String = "Groceries", monthsAgo: Int = 0) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return .test(timestamp: date, amount: -abs(amount), category: category)
    }

    @Test("healthScore is nil when no income and no expenses in recent 6 months")
    func healthScoreNilWithoutRecentTransactions() async {
        let vm = await makeVM(transactions: [])
        #expect(vm.healthScore == nil)
    }

    @Test("healthScore is not nil when income exists in recent 6 months")
    func healthScoreNotNilWithRecentIncome() async {
        let income = makeIncome(amount: 1000, monthsAgo: 0)
        let vm = await makeVM(transactions: [income])
        #expect(vm.healthScore != nil)
    }

    @Test("healthScore is not nil when expenses exist in recent 6 months")
    func healthScoreNotNilWithRecentExpense() async {
        let expense = makeExpense(amount: 100, monthsAgo: 0)
        let vm = await makeVM(transactions: [expense])
        #expect(vm.healthScore != nil)
    }
}
