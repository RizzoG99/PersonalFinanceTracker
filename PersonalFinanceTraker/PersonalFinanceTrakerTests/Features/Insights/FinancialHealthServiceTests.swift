import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite("FinancialHealthService")
struct FinancialHealthServiceTests {

    private func makeService() -> FinancialHealthService {
        FinancialHealthService(currencyService: CurrencyService())
    }

    private func makeIncome(amount: Decimal, monthsAgo: Int = 0) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return .test(timestamp: date, amount: amount, category: "Salary")
    }

    private func makeExpense(amount: Decimal, category: String = "Groceries", monthsAgo: Int = 0) -> TransactionSnapshot {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return .test(timestamp: date, amount: -abs(amount), category: category)
    }

    @Test("tip is nil when savings score is maxed (≥20% savings rate)")
    func savingsTipNilWhenMaxed() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 700, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        // Savings is always the first component (see FinancialHealthService.compute);
        // match by position rather than localized name so the test is locale-independent.
        let savings = result.components[0]
        #expect(savings.tip == nil)
    }

    @Test("tip is non-nil when savings score is below max")
    func savingsTipPresentWhenBelowMax() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 900, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        // Savings is always the first component (see FinancialHealthService.compute);
        // match by position rather than localized name so the test is locale-independent.
        let savings = result.components[0]
        #expect(savings.tip != nil)
    }

    @Test("explanation is non-empty for all components")
    func allExplanationsNonEmpty() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 800, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        for component in result.components {
            #expect(!component.explanation.isEmpty)
        }
    }

    // MARK: - #342: the cycle's last day counts

    private let lastDayNow = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18))!
    private let lastDayAfternoon = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 17))!

    @Test("budget adherence counts an overspend on the cycle's last day")
    func adherenceCountsLastDay() {
        let result = makeService().compute(
            transactions: [],
            expenseTransactions: [.test(timestamp: lastDayAfternoon, amount: -60, category: "Fun")],
            budgetedCategories: [.test(name: "Fun", monthlyBudget: 50)],
            now: lastDayNow
        )
        // Budget is the third component (see FinancialHealthService.compute).
        #expect(result.components[2].score == 0)
    }

    @Test("spending stability counts the cycle's last day")
    func stabilityCountsLastDay() {
        let calendar = Calendar.current
        let earlier = (5...9).map { month in
            TransactionSnapshot.test(
                timestamp: calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!,
                amount: -100, category: "Groceries"
            )
        }
        let expenses = earlier + [.test(timestamp: lastDayAfternoon, amount: -100, category: "Groceries")]
        let result = makeService().compute(
            transactions: expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            now: lastDayNow
        )
        // Stability is the second component: the same spend every month scores full marks.
        #expect(result.components[1].score == 25)
    }

    @Test("ignoreSubscriptions produces 3 components summing to ≤100")
    func optOutGivesThreeComponents() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 800, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: true
        )
        #expect(result.components.count == 3)
        #expect(result.score <= 100)
        #expect(result.score >= 0)
    }

    @Test("ignoreSubscriptions maxes at 100 when all components are perfect")
    func optOutMaxScore() {
        let service = makeService()
        // Perfect savings (>20%), stable spending, no budget categories
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 700, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: true
        )
        #expect(result.components.map(\.max).reduce(0, +) == 100)
    }

    @Test("MockRepository saveSnapshot is called after compute")
    func snapshotSavedAfterCompute() async throws {
        let mock = MockTransactionRepository()
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 800, monthsAgo: $0) }
        mock.stubbedTransactions = income + expenses

        // Simulate what CompassViewModel.saveSnapshotIfNeeded does
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        let snapshot = HealthScoreSnapshotData(
            timestamp: Date.now,
            score: result.score,
            savingsScore: result.components.first(where: { $0.name == "Savings rate" })?.score ?? 0,
            stabilityScore: result.components.first(where: { $0.name == "Stability" })?.score ?? 0,
            adherenceScore: result.components.first(where: { $0.name == "Budget" })?.score ?? 0,
            subscriptionScore: result.components.first(where: { $0.name == "Subscriptions" })?.score ?? 0
        )
        try await mock.saveSnapshot(snapshot)
        let fetched = try await mock.fetchSnapshots(limit: 6)

        #expect(mock.saveSnapshotCalledCount == 1)
        #expect(fetched.count == 1)
        #expect(fetched.first?.score == result.score)
    }

    @Test("Snapshot subscriptionScore is 0 when ignoreSubscriptions is true")
    func snapshotSubscriptionScoreZeroWhenIgnored() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 800, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: true
        )
        // When opt-out is on, there is no "Subscriptions" component
        let subscriptionComponent = result.components.first(where: { $0.name == "Subscriptions" })
        #expect(subscriptionComponent == nil)
        // Snapshot extraction should use 0 explicitly (not rely on nil-coalescence)
        let subscriptionScore = result.components.first(where: { $0.name == "Subscriptions" })?.score ?? 0
        #expect(subscriptionScore == 0)
    }
}
