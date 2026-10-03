import Testing
import Foundation
import SwiftUI
@testable import PersonalFinanceTraker

private let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.firstWeekday = 2 // Monday
    return cal
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

struct ExplorerPeriodTests {

    @Test func monthIsTheCalendarMonthEndExclusive() {
        let p = ExplorerPeriod.current(.month, now: date(2026, 9, 15), calendar: utc)
        #expect(p.interval.start == date(2026, 9, 1, 0))
        #expect(p.interval.end == date(2026, 10, 1, 0))
    }

    @Test func previousAndNextCrossTheYearBoundary() {
        let jan = ExplorerPeriod.current(.month, now: date(2026, 1, 10), calendar: utc)
        #expect(jan.previous(calendar: utc).interval.start == date(2025, 12, 1, 0))
        let dec = ExplorerPeriod.current(.month, now: date(2025, 12, 10), calendar: utc)
        #expect(dec.next(calendar: utc).interval.start == date(2026, 1, 1, 0))
        let week = ExplorerPeriod.current(.week, now: date(2026, 1, 1), calendar: utc) // Thursday
        #expect(week.interval.start == date(2025, 12, 29, 0)) // Monday
        #expect(week.previous(calendar: utc).interval.start == date(2025, 12, 22, 0))
    }

    @Test func nextIsDisabledOnlyForTheCurrentPeriod() {
        let now = date(2026, 9, 15)
        let current = ExplorerPeriod.current(.month, now: now, calendar: utc)
        #expect(current.isCurrent(now: now))
        #expect(!current.previous(calendar: utc).isCurrent(now: now))
    }

    @Test func customRangeIsWholeDaysAndStepsByItsOwnLength() {
        let p = ExplorerPeriod.custom(from: date(2026, 8, 3, 15), through: date(2026, 8, 12, 9), calendar: utc)
        #expect(p.interval.start == date(2026, 8, 3, 0))
        #expect(p.interval.end == date(2026, 8, 13, 0)) // 10 days, Aug 12 included
        let prev = p.previous(calendar: utc)
        #expect(prev.interval.start == date(2026, 7, 24, 0))
        #expect(prev.interval.end == date(2026, 8, 3, 0))
        #expect(p.comparisonInterval(now: date(2026, 9, 1), calendar: utc) == prev.interval)
    }

    @Test func finishedPeriodComparesWithTheWholePreviousOne() {
        let aug = ExplorerPeriod.current(.month, now: date(2026, 8, 10), calendar: utc)
        let cmp = aug.comparisonInterval(now: date(2026, 9, 15), calendar: utc)
        #expect(cmp == DateInterval(start: date(2026, 7, 1, 0), end: date(2026, 8, 1, 0)))
    }

    @Test func inProgressPeriodComparesTheSameElapsedStretch() {
        let now = date(2026, 9, 10, 0)
        let sep = ExplorerPeriod.current(.month, now: now, calendar: utc)
        let cmp = sep.comparisonInterval(now: now, calendar: utc)
        #expect(cmp == DateInterval(start: date(2026, 8, 1, 0), end: date(2026, 8, 10, 0)))
    }

    /// Mar 31: 30 elapsed days would run past the end of February — clamp to it.
    @Test(arguments: [2026, 2028]) // 2028: Feb 29
    func comparisonIsClampedToThePreviousPeriodsEnd(year: Int) {
        let now = date(year, 3, 31, 18)
        let mar = ExplorerPeriod.current(.month, now: now, calendar: utc)
        let cmp = mar.comparisonInterval(now: now, calendar: utc)
        #expect(cmp.start == date(year, 2, 1, 0))
        #expect(cmp.end == date(year, 3, 1, 0))
    }
}

struct ExplorerBreakdownTests {
    let service = PieChartDataService()
    let sep = ExplorerPeriod.current(.month, now: date(2026, 9, 15), calendar: utc)
    let now = date(2026, 10, 5) // September is finished

    /// The drill-down list must add up to its row: same filter, same grouping, same currency.
    @Test func everyRowEqualsTheSumOfItsDrillDown() {
        let txs: [TransactionSnapshot] = [
            .test(timestamp: date(2026, 9, 3), amount: -40, category: "🍕 Food"),
            .test(timestamp: date(2026, 9, 1, 0), amount: -10, category: "🍕 Food"),       // first instant: in
            .test(timestamp: date(2026, 10, 1, 0), amount: -999, category: "🍕 Food"),     // next period: out
            .test(timestamp: date(2026, 9, 4), amount: -25, category: ""),                 // → "Other"
            .test(timestamp: date(2026, 9, 5), amount: -30, category: "🍕 Food", currencyCode: "USD"),
            .test(timestamp: date(2026, 9, 6), amount: -500, category: "🎯 Goal", goalId: UUID()), // transfer: out
            .test(timestamp: date(2026, 9, 7), amount: 2000, category: "💼 Salary"),       // income: out
        ]
        let breakdown = ExplorerBreakdown(transactions: txs, categories: [], period: sep, dataType: .expenses, now: now, calendar: utc)

        #expect(Set(breakdown.trends.map(\.category.category)) == ["🍕 Food", "Other"])
        for trend in breakdown.trends {
            let drillDown = service.explorerItems(txs, in: sep.interval, dataType: .expenses)
                .filter { service.groupingKey(for: $0) == trend.category.category }
            #expect(service.categoryTotals(drillDown)[trend.category.category] == trend.category.amount)
        }
        #expect(breakdown.total == breakdown.trends.reduce(0) { $0 + $1.category.amount })
        #expect(breakdown.bars.reduce(Decimal(0)) { $0 + $1.amount } == breakdown.total)
    }

    @Test func deltaComparesWithThePreviousPeriodAndFlagsNewCategories() {
        let txs: [TransactionSnapshot] = [
            .test(timestamp: date(2026, 8, 10), amount: -100, category: "🍕 Food"),
            .test(timestamp: date(2026, 9, 10), amount: -150, category: "🍕 Food"),
            .test(timestamp: date(2026, 9, 11), amount: -20, category: "🎬 Fun"),
        ]
        let trends = ExplorerBreakdown(transactions: txs, categories: [], period: sep, dataType: .expenses, now: now, calendar: utc).trends
        let food = trends.first { $0.category.category == "🍕 Food" }
        let fun = trends.first { $0.category.category == "🎬 Fun" }
        #expect(food?.direction == .up)
        #expect(Int(food?.changePercent ?? 0) == 50)
        #expect(fun?.isNew == true)
        #expect(fun?.changePercent == 0) // "new", not an infinite %
    }

    /// #154: in-progress month, identical pace → flat, and a future-dated recurring charge
    /// doesn't count toward the pace (it still shows in the row amount).
    @Test func inProgressDeltaIsPaceBased() {
        let midSep = date(2026, 9, 15)
        let txs: [TransactionSnapshot] = [
            .test(timestamp: date(2026, 8, 5), amount: -50, category: "🍕 Food"),
            .test(timestamp: date(2026, 8, 25), amount: -50, category: "🍕 Food"), // after Aug 15: not compared
            .test(timestamp: date(2026, 9, 5), amount: -50, category: "🍕 Food"),
            .test(timestamp: date(2026, 9, 28), amount: -500, category: "🍕 Food"), // future-dated
        ]
        let food = ExplorerBreakdown(transactions: txs, categories: [], period: sep, dataType: .expenses, now: midSep, calendar: utc)
            .trends.first
        #expect(food?.category.amount == 550)
        #expect(food?.direction == .flat)
    }

    /// Regression: an income and an expense category named the same used to trap
    /// `Dictionary(uniqueKeysWithValues:)` and crash Insights on launch.
    @Test func sameNamedIncomeAndExpenseCategoriesDoNotCrashAndUseTheMatchingType() {
        let categories: [CategorySnapshot] = [
            .test(name: "Other", type: .income, colorToken: "categoryGreen"),
            .test(name: "Other", type: .expense, colorToken: "categoryRed"),
        ]
        let txs: [TransactionSnapshot] = [.test(timestamp: date(2026, 9, 3), amount: -40, category: "Other")]
        let slice = ExplorerBreakdown(transactions: txs, categories: categories, period: sep, dataType: .expenses, now: now, calendar: utc)
            .trends.first?.category
        #expect(slice?.amount == 40)
        #expect(slice?.color == Color(categoryToken: "categoryRed"))
    }

    @Test func yearHasOneBarPerMonthAndMonthOnePerDay() {
        let year = ExplorerPeriod.current(.year, now: date(2026, 5, 1), calendar: utc)
        #expect(ExplorerBreakdown(transactions: [], categories: [], period: year, dataType: .expenses, now: now, calendar: utc).bars.count == 12)
        #expect(ExplorerBreakdown(transactions: [], categories: [], period: sep, dataType: .expenses, now: now, calendar: utc).bars.count == 30)
    }
}

struct UpcomingChargeTests {
    @Test func soonestNextExpenseChargePerRuleStillToHappen() {
        let now = date(2026, 9, 15, 18)
        let rules: [RecurrenceRuleSnapshot] = [
            .test(startDate: date(2026, 1, 20, 9), amount: -13, category: "Netflix"),
            .test(startDate: date(2026, 1, 15, 8), amount: -800, category: "Rent"),        // today 08:00 already happened → Oct 15
            .test(startDate: date(2026, 1, 15, 22), amount: -9, category: "Gym"),         // today 22:00 still ahead
            .test(startDate: date(2026, 1, 27, 9), amount: 2000, category: "Salary"),     // income: skipped
            .test(startDate: date(2026, 1, 16, 9), endDate: date(2026, 6, 1), amount: -5, category: "Ended"),
        ]
        let charges = UpcomingCharge.next(rules: rules, now: now, calendar: utc)
        #expect(charges.map(\.rule.category) == ["Gym", "Netflix", "Rent"])
        #expect(charges.last?.date == date(2026, 10, 15, 8))
    }

    /// Regression (manual test): a rule created and stopped the same day, after its only charge
    /// was recorded, kept showing as "Today" in Plan.
    @Test func ruleStoppedRightAfterItsOnlyChargeIsGone() {
        let rule = RecurrenceRuleSnapshot.test(
            startDate: date(2026, 10, 3, 18), endDate: date(2026, 10, 3, 18).addingTimeInterval(200),
            lastMaterializedDate: date(2026, 10, 3, 18), amount: -20, category: "Streaming Services"
        )
        #expect(UpcomingCharge.next(rules: [rule], now: date(2026, 10, 3, 20), calendar: utc).isEmpty)
    }

    @Test func respectsTheLimit() {
        let rules = (1...8).map { RecurrenceRuleSnapshot.test(startDate: date(2026, 1, $0 + 15), amount: -1, category: "R\($0)") }
        #expect(UpcomingCharge.next(rules: rules, now: date(2026, 9, 1), limit: 5, calendar: utc).count == 5)
    }
}
