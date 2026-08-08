import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite("SpendingInsightService")
struct SpendingInsightServiceTests {

    private func makeService() -> SpendingInsightService {
        SpendingInsightService(currencyService: CurrencyService(), pieDataService: PieChartDataService())
    }

    // Returns a date that lands on a specific weekday (1=Sun, 7=Sat) within the last 30 days
    private func dateOnWeekday(_ weekday: Int, weeksAgo: Int = 0) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = weekday
        components.weekOfYear = (components.weekOfYear ?? 0) - weeksAgo
        return cal.date(from: components) ?? Date()
    }

    private func makeExpense(amount: Decimal, category: String = "🛒 Groceries", on date: Date) -> TransactionSnapshot {
        .test(timestamp: date, amount: -abs(amount), category: category)
    }

    // Returns a Date in a specific calendar week, offset from current week
    private func dateInWeek(weeksAgo: Int, weekday: Int = 3) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekOfYear = (comps.weekOfYear ?? 0) - weeksAgo
        comps.weekday = weekday
        return cal.date(from: comps) ?? Date()
    }

    @Test("4-week streak emits streak observation with 'over a month' detail")
    func fourWeekStreakEmitsObservation() {
        let service = makeService()
        // One transaction per week for 4 consecutive weeks in same category
        let txns = (0..<4).map { makeExpense(amount: 20, category: "🛒 Groceries", on: dateInWeek(weeksAgo: $0)) }
        let obs = service.habitObservations(expenseTransactions: txns)
        // Compared against the same localized lookups SpendingInsightService uses rather than
        // hardcoded English literals, so this doesn't depend on the test device's language.
        let expectedTitle = String(localized: "\("Groceries".localizedCategoryDisplay) — \(4)-week streak")
        let streak = obs.first { $0.title == expectedTitle }
        #expect(streak != nil)
        #expect(streak?.detail == String(localized: "Every week for over a month"))
    }

    @Test("weekend-heavy: emits calendar.badge.clock observation")
    func weekendHeavySpending() {
        let service = makeService()
        // 5 weekend transactions × €50 = €250 total weekend, avg €25/day (€250/10)
        // 5 weekday transactions × €10 = €50 total weekday, avg €2.5/day (€50/20)
        // ratio = 10× — well above 1.3 threshold
        let weekend = (0..<5).map { makeExpense(amount: 50, on: dateOnWeekday(7, weeksAgo: $0 % 4)) }
        let weekday = (0..<5).map { makeExpense(amount: 10, on: dateOnWeekday(2, weeksAgo: $0 % 4)) }
        let obs = service.habitObservations(expenseTransactions: weekend + weekday)
        #expect(obs.contains { $0.sfSymbol == "calendar.badge.clock" })
    }

    @Test("fewer than 5 expenses: no weekend/weekday observation")
    func tooFewExpensesSkipsWeekendWeekday() {
        let service = makeService()
        let txns = (0..<4).map { makeExpense(amount: 50, on: dateOnWeekday(7, weeksAgo: $0)) }
        let obs = service.habitObservations(expenseTransactions: txns)
        #expect(!obs.contains { $0.sfSymbol == "calendar.badge.clock" || $0.sfSymbol == "briefcase" })
    }

    @Test("2-week streak emits no streak observation")
    func twoWeekStreakTooShort() {
        let service = makeService()
        let txns = (0..<2).map { makeExpense(amount: 20, category: "🛒 Groceries", on: dateInWeek(weeksAgo: $0)) }
        let obs = service.habitObservations(expenseTransactions: txns)
        #expect(!obs.contains { $0.title.contains("streak") })
    }

    @Test("at most 2 streak observations emitted")
    func atMostTwoStreaks() {
        let service = makeService()
        // 3 categories each with 4-week streaks
        let cats = ["🛒 Groceries", "🍽️ Restaurants", "⛽ Gas"]
        let txns = cats.flatMap { cat in
            (0..<4).map { makeExpense(amount: 20, category: cat, on: dateInWeek(weeksAgo: $0)) }
        }
        let obs = service.habitObservations(expenseTransactions: txns)
        #expect(obs.filter { $0.title.contains("streak") }.count <= 2)
    }

    @Test("trivial amounts: no weekend/weekday observation despite ratio ≥ 1.3")
    func trivialAmountsSkipWeekendWeekday() {
        let service = makeService()
        // weekend avg = €15/10 = €1.5/day, weekday avg = €10/20 = €0.5/day — ratio = 3× but both trivial
        let weekend = (0..<5).map { makeExpense(amount: 3, on: dateOnWeekday(7, weeksAgo: $0 % 4)) }
        let weekday = (0..<5).map { makeExpense(amount: 2, on: dateOnWeekday(2, weeksAgo: $0 % 4)) }
        let obs = service.habitObservations(expenseTransactions: weekend + weekday)
        #expect(!obs.contains { $0.sfSymbol == "calendar.badge.clock" || $0.sfSymbol == "briefcase" })
    }

    @Test("weekday-heavy: emits briefcase observation")
    func weekdayHeavySpending() {
        let service = makeService()
        // 5 weekday transactions × €50 = €250 total weekday, avg €12.5/day (€250/20)
        // 5 weekend transactions × €10 = €50 total weekend, avg €5/day (€50/10)
        // inverse ratio = 2.5× — well above 1.3 threshold
        let weekday = (0..<5).map { makeExpense(amount: 50, on: dateOnWeekday(2, weeksAgo: $0 % 4)) }
        let weekend = (0..<5).map { makeExpense(amount: 10, on: dateOnWeekday(7, weeksAgo: $0 % 4)) }
        let obs = service.habitObservations(expenseTransactions: weekday + weekend)
        #expect(obs.contains { $0.sfSymbol == "briefcase" })
    }
}
