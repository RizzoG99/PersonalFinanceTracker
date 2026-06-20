import Testing
@testable import PersonalFinanceTraker
import Foundation

@Suite(.serialized)
struct ChartDataServiceTests {

    private func makeExpense(on date: Date, amount: Decimal = -50) -> TransactionModel {
        TransactionModel(timestamp: date, amount: amount, note: "", category: "Food", currencyCode: "EUR")
    }

    @Test func monthFilterUsesFinancialMonthStart() {
        let service = ChartDataService()
        let startDay = 10
        let (financialStart, _) = PayCycleService.currentFinancialMonth(startDay: startDay)
        let calendar = Calendar.current

        let beforeStart = calendar.date(byAdding: .day, value: -1, to: financialStart)!
        let onStart = financialStart
        let afterStart = calendar.date(byAdding: .day, value: 1, to: financialStart)!

        let transactions = [
            makeExpense(on: beforeStart),
            makeExpense(on: onStart),
            makeExpense(on: afterStart)
        ]

        let filtered = service.filterItems(transactions, for: .month, payCycleStartDay: startDay)
        #expect(filtered.count == 2)
    }

    @Test func weekFilterUnchangedByPayCycleStartDay() {
        let service = ChartDataService()
        let now = Date.now
        let calendar = Calendar.current
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        let transactions = [
            makeExpense(on: tenDaysAgo),
            makeExpense(on: threeDaysAgo)
        ]

        let filtered = service.filterItems(transactions, for: .week, payCycleStartDay: 15)
        #expect(filtered.count == 1)
    }

    @Test func defaultStartDayMatchesCalendarMonth() {
        let service = ChartDataService()
        let calendar = Calendar.current
        let now = Date.now
        let calendarMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        let beforeMonthStart = calendar.date(byAdding: .day, value: -1, to: calendarMonthStart)!
        let afterMonthStart = calendar.date(byAdding: .day, value: 1, to: calendarMonthStart)!

        let transactions = [
            makeExpense(on: beforeMonthStart),
            makeExpense(on: afterMonthStart)
        ]

        // payCycleStartDay = 1 → financial month = calendar month
        let filtered = service.filterItems(transactions, for: .month, payCycleStartDay: 1)
        #expect(filtered.count == 1)
    }
}
