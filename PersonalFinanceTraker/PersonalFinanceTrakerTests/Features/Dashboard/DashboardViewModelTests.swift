import Testing
@testable import PersonalFinanceTraker
import Foundation

@MainActor
@Suite(.serialized)
struct DashboardViewModelTests {

    private func makeVM(transactions: [TransactionSnapshot]) async -> DashboardViewModel {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = transactions
        let vm = DashboardViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        return vm
    }

    private func makeTx(daysAgo: Int, amount: Decimal) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date.now)!
        return TransactionSnapshot.test(timestamp: date, amount: amount, note: "", category: "Test", currencyCode: "EUR")
    }

    @Test func excludesTransactionBeforeFinancialMonthStart() async {
        let (financialStart, _) = PayCycleService.currentFinancialMonth(startDay: 10)
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: financialStart)!
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: financialStart)!

        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [
            TransactionSnapshot.test(timestamp: dayBefore, amount: 1000, note: "", category: "Salary", currencyCode: "EUR"),
            TransactionSnapshot.test(timestamp: dayAfter, amount: 500, note: "", category: "Salary", currencyCode: "EUR")
        ]
        let vm = DashboardViewModel(repo: repo)
        vm.payCycleStartDay = { 10 }
        vm.load()
        await vm.loadTask?.value

        #expect(vm.monthlyIncome == 500)
    }

    @Test func includesTransactionOnFinancialMonthStart() async {
        let (financialStart, _) = PayCycleService.currentFinancialMonth(startDay: 10)

        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [
            TransactionSnapshot.test(timestamp: financialStart, amount: -200, note: "", category: "Food", currencyCode: "EUR")
        ]
        let vm = DashboardViewModel(repo: repo)
        vm.payCycleStartDay = { 10 }
        vm.load()
        await vm.loadTask?.value

        #expect(vm.monthlyExpenses == 200)
    }

    @Test func financialMonthLabelShowsDatesWhenNotFirstOfMonth() async {
        UserDefaults.standard.set(10, forKey: "payCycleStartDay")
        defer { UserDefaults.standard.removeObject(forKey: "payCycleStartDay") }

        let vm = DashboardViewModel(repo: MockTransactionRepository())
        #expect(vm.financialMonthLabel != "This Month")
    }

    @Test func financialMonthLabelIsThisMonthWhenStartDayIsOne() async {
        UserDefaults.standard.removeObject(forKey: "payCycleStartDay")
        let vm = DashboardViewModel(repo: MockTransactionRepository())
        #expect(vm.financialMonthLabel == "This Month")
    }

    @Test func calculatesAllMetricsInSingleLoad() async {
        UserDefaults.standard.set(1, forKey: "payCycleStartDay")
        defer { UserDefaults.standard.removeObject(forKey: "payCycleStartDay") }

        // 3 transactions this month: +1000 income, -300 expense, -200 expense
        let (monthStart, _) = PayCycleService.currentFinancialMonth(startDay: 1)
        let repo = MockTransactionRepository()
        let calendar = Calendar.current
        repo.stubbedTransactions = [
            TransactionSnapshot.test(timestamp: calendar.date(byAdding: .hour, value: 2, to: monthStart)!, amount: 1000, note: "", category: "Salary", currencyCode: "EUR"),
            TransactionSnapshot.test(timestamp: calendar.date(byAdding: .hour, value: 1, to: monthStart)!, amount: -300, note: "", category: "Food", currencyCode: "EUR"),
            TransactionSnapshot.test(timestamp: monthStart, amount: -200, note: "", category: "Transport", currencyCode: "EUR"),
        ]
        let vm = DashboardViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value

        #expect(vm.totalBalance == 500)
        #expect(vm.monthlyIncome == 1000)
        #expect(vm.monthlyExpenses == 500)
        #expect(vm.recentTransactions.count == 3)
        // Most recent first
        #expect(vm.recentTransactions.first?.amount == 1000)
    }

    @Test func loadDoesNotRefetchWhenAlreadyLoaded() async throws {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [makeTx(daysAgo: 1, amount: -100)]
        let vm = DashboardViewModel(repo: repo)

        vm.load()
        await vm.loadTask?.value
        #expect(vm.transactions.count == 1)

        // Mutate the underlying repo after first load
        repo.stubbedTransactions = [makeTx(daysAgo: 1, amount: -100), makeTx(daysAgo: 2, amount: -200)]

        // Second load() must be a no-op
        vm.load()
        await vm.loadTask?.value
        #expect(vm.transactions.count == 1)  // still 1, not 2
    }

    @Test func reloadFetchesFreshData() async throws {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [makeTx(daysAgo: 1, amount: -100)]
        let vm = DashboardViewModel(repo: repo)

        vm.load()
        await vm.loadTask?.value
        #expect(vm.transactions.count == 1)

        repo.stubbedTransactions = [makeTx(daysAgo: 1, amount: -100), makeTx(daysAgo: 2, amount: -200)]

        vm.reload()
        await vm.loadTask?.value
        #expect(vm.transactions.count == 2)
    }

    @Test func zeroAmountTransactionDoesNotAffectMonthlyMetrics() async {
        UserDefaults.standard.set(1, forKey: "payCycleStartDay")
        defer { UserDefaults.standard.removeObject(forKey: "payCycleStartDay") }
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [
            TransactionSnapshot.test(timestamp: Date(), amount: 0, note: "", category: "Test", currencyCode: "EUR")
        ]
        let vm = DashboardViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        #expect(vm.monthlyIncome == 0)
        #expect(vm.monthlyExpenses == 0)
    }

    @Test func anomalyCalloutDetectsSpike() {
        // One large expense today, otherwise-quiet pay cycle → spike week flagged
        let transactions = [
            TransactionSnapshot.test(timestamp: .now, amount: -1000, category: "Shopping")
        ]
        let callout = DashboardViewModel.computeAnomalyCallout(
            transactions, payCycleStartDay: 1, dismissedKey: nil
        )
        #expect(callout != nil)
        #expect(callout?.message.contains("€") == true)
    }

    @Test func anomalyCalloutRespectsDismissal() {
        let transactions = [
            TransactionSnapshot.test(timestamp: .now, amount: -1000, category: "Shopping")
        ]
        let first = DashboardViewModel.computeAnomalyCallout(
            transactions, payCycleStartDay: 1, dismissedKey: nil
        )
        let second = DashboardViewModel.computeAnomalyCallout(
            transactions, payCycleStartDay: 1, dismissedKey: first?.dismissKey
        )
        #expect(second == nil)
    }

    @Test func anomalyCalloutNilWithoutSpike() {
        let callout = DashboardViewModel.computeAnomalyCallout(
            [], payCycleStartDay: 1, dismissedKey: nil
        )
        #expect(callout == nil)
    }
}
