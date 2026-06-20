import Testing
@testable import PersonalFinanceTraker
import Foundation

@MainActor
@Suite(.serialized)
struct DashboardViewModelTests {

    private func makeVM(transactions: [TransactionModel]) -> DashboardViewModel {
        let repo = MockTransactionRepository()
        repo.transactions = transactions
        let vm = DashboardViewModel(repo: repo)
        vm.load()
        return vm
    }

    private func makeTx(daysAgo: Int, amount: Decimal) -> TransactionModel {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date.now)!
        return TransactionModel(timestamp: date, amount: amount, note: "", category: "Test", currencyCode: "EUR")
    }

    @Test func excludesTransactionBeforeFinancialMonthStart() {
        // Set payCycleStartDay = 10 in UserDefaults
        UserDefaults.standard.set(10, forKey: "payCycleStartDay")
        defer { UserDefaults.standard.removeObject(forKey: "payCycleStartDay") }

        let (financialStart, _) = PayCycleService.currentFinancialMonth(startDay: 10)
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: financialStart)!
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: financialStart)!

        let repo = MockTransactionRepository()
        repo.transactions = [
            TransactionModel(timestamp: dayBefore, amount: 1000, note: "", category: "Salary", currencyCode: "EUR"),
            TransactionModel(timestamp: dayAfter, amount: 500, note: "", category: "Salary", currencyCode: "EUR")
        ]
        let vm = DashboardViewModel(repo: repo)
        vm.load()

        #expect(vm.monthlyIncome == 500)
    }

    @Test func includesTransactionOnFinancialMonthStart() {
        UserDefaults.standard.set(10, forKey: "payCycleStartDay")
        defer { UserDefaults.standard.removeObject(forKey: "payCycleStartDay") }

        let (financialStart, _) = PayCycleService.currentFinancialMonth(startDay: 10)

        let repo = MockTransactionRepository()
        repo.transactions = [
            TransactionModel(timestamp: financialStart, amount: -200, note: "", category: "Food", currencyCode: "EUR")
        ]
        let vm = DashboardViewModel(repo: repo)
        vm.load()

        #expect(vm.monthlyExpenses == 200)
    }

    @Test func financialMonthLabelShowsDatesWhenNotFirstOfMonth() {
        UserDefaults.standard.set(10, forKey: "payCycleStartDay")
        defer { UserDefaults.standard.removeObject(forKey: "payCycleStartDay") }

        let vm = DashboardViewModel(repo: MockTransactionRepository())
        #expect(vm.financialMonthLabel != "This Month")
    }

    @Test func financialMonthLabelIsThisMonthWhenStartDayIsOne() {
        UserDefaults.standard.removeObject(forKey: "payCycleStartDay")
        let vm = DashboardViewModel(repo: MockTransactionRepository())
        #expect(vm.financialMonthLabel == "This Month")
    }
}
