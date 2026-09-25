import Testing
@testable import PersonalFinanceTraker
import Foundation
import SwiftData

@Suite(.serialized)
struct ChartDataServiceTests {

    private func makeExpense(on date: Date, amount: Decimal = -50) -> TransactionSnapshot {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: TransactionModel.self, configurations: config)
        let ctx = ModelContext(container)
        let model = TransactionModel(timestamp: date, amount: amount, note: "", category: "Food", currencyCode: "EUR")
        ctx.insert(model)
        try! ctx.save()
        return TransactionSnapshot(model)
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

    /// #154: a transaction on the very last day of the financial month used to be dropped by
    /// the old `<= end`-at-midnight bound.
    @Test func monthFilterIncludesLastDayOfFinancialMonth() {
        let service = ChartDataService()
        let (start, end) = PayCycleService.currentFinancialMonth(startDay: 1)
        let calendar = Calendar.current
        let lastDayEvening = calendar.date(byAdding: .hour, value: 23, to: end) ?? end

        let filtered = service.filterItems([makeExpense(on: lastDayEvening)], for: .month, referenceDate: start, payCycleStartDay: 1)
        #expect(filtered.count == 1)
    }

    /// #154: the yearly chart used to show a partial in-progress month as its last point,
    /// collapsing near zero next to 12 full months. It should show 12 *complete* months instead.
    @Test func yearlyDataShowsTwelveCompleteMonthsNotTheCurrentOne() {
        let service = ChartDataService()
        let calendar = Calendar.current
        // Anchor mid-month so "the current month" definitely has fewer days of data than a
        // complete month would, making a regression to the old behavior visible.
        var comps = calendar.dateComponents([.year, .month], from: .now)
        comps.day = 15
        let referenceDate = calendar.date(from: comps)!

        // One equal-amount expense a few days into each of the last 13 financial months
        // (including the in-progress one), so every *complete* month has the same total and a
        // leaked-in partial month would be conspicuously absent instead of just lower.
        let months = PayCycleService.financialMonths(count: 13, before: referenceDate, startDay: 1)
        let transactions = months.map { month in
            makeExpense(on: calendar.date(byAdding: .day, value: 5, to: month.start)!, amount: -10)
        }

        let data = service.generateChartData(from: transactions, for: .year, referenceDate: referenceDate, payCycleStartDay: 1)
        #expect(data.count == 12)
        #expect(data.allSatisfy { $0.expenses == 10 }, "all 12 complete months should have equal totals; got \(data.map { $0.expenses })")
    }

    /// #154: points must be oldest→newest, and be the 12 complete financial months immediately
    /// before the in-progress one — computed independently via `PayCycleService.financialMonths`
    /// rather than derived from `data` itself, so this actually guards against a stray
    /// `.reversed()`, an off-by-one in the `dropLast()`, or a label misaligned with its window.
    @Test func yearlyDataPointsAreOrderedOldestToNewestWithMatchingLabels() {
        let service = ChartDataService()
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month], from: .now)
        comps.day = 15
        let referenceDate = calendar.date(from: comps)!

        let expectedMonths = PayCycleService.financialMonths(count: 13, before: referenceDate, startDay: 1).dropLast()
        let data = service.generateChartData(from: [], for: .year, referenceDate: referenceDate, payCycleStartDay: 1)

        #expect(data.count == 12)
        #expect(zip(data, expectedMonths).allSatisfy { point, month in
            point.date == month.start && point.period == month.start.formatted(.dateTime.month(.abbreviated))
        })
    }

    @Test func yearlyDataRespectsPayCycleStartDay() {
        let service = ChartDataService()
        let calendar = Calendar.current
        let startDay = 10
        var comps = calendar.dateComponents([.year, .month], from: .now)
        comps.day = 20
        let referenceDate = calendar.date(from: comps)!

        let data = service.generateChartData(from: [], for: .year, referenceDate: referenceDate, payCycleStartDay: startDay)
        #expect(data.allSatisfy { calendar.component(.day, from: $0.date) == startDay })
    }
}
