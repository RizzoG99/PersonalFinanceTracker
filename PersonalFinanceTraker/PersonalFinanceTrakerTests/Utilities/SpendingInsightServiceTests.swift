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

    private func makeExpense(amount: Decimal, category: String = "🛒 Groceries", on date: Date) -> TransactionModel {
        TransactionModel(timestamp: date, amount: -abs(amount), note: "", category: category, currencyCode: "EUR", goalId: nil)
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
}
