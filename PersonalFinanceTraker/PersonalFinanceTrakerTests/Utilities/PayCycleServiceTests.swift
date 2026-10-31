import Testing
import Foundation

@testable import PersonalFinanceTraker

struct PayCycleServiceTests {
    let calendar = Calendar.current

    @Test("financialMonthStart returns correct start for date after start day")
    func financialMonthStartAfterStartDay() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let startDay = 10

        let result = PayCycleService.financialMonthStart(for: date, startDay: startDay, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        #expect(result == expected)
    }

    @Test("financialMonthStart returns previous month start for date before start day")
    func financialMonthStartBeforeStartDay() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let startDay = 10

        let result = PayCycleService.financialMonthStart(for: date, startDay: startDay, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2025, month: 12, day: 10))!

        #expect(result == expected)
    }

    @Test("financialMonthStart handles start day on exact date")
    func financialMonthStartOnExactDate() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let startDay = 10

        let result = PayCycleService.financialMonthStart(for: date, startDay: startDay, calendar: calendar)

        #expect(result == date)
    }

    @Test("financialMonths returns correct count and boundaries")
    func financialMonthsCount() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let startDay = 10

        let months = PayCycleService.financialMonths(count: 3, before: referenceDate, startDay: startDay, calendar: calendar)

        #expect(months.count == 3)
    }

    @Test("financialMonths returns months in ascending order")
    func financialMonthsAscendingOrder() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let startDay = 10

        let months = PayCycleService.financialMonths(count: 3, before: referenceDate, startDay: startDay, calendar: calendar)

        for i in 1..<months.count {
            #expect(months[i].start > months[i - 1].start)
        }
    }

    @Test("currentFinancialMonth returns valid window")
    func currentFinancialMonthValidity() {
        let startDay = 10

        let (start, end) = PayCycleService.currentFinancialMonth(startDay: startDay, calendar: calendar)

        #expect(start < end)
        #expect(start <= Date.now)
    }

    /// #342: `end` is the cycle's last instant, so `<= end` filters keep its whole last day.
    @Test("currentFinancialMonth ends at the last instant of the cycle's last day")
    func currentFinancialMonthEndsAtLastInstant() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18))!
        let nextStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!

        let (_, end) = PayCycleService.currentFinancialMonth(startDay: 1, now: now, calendar: calendar)

        #expect(end == nextStart.addingTimeInterval(-0.001))
        #expect(calendar.component(.day, from: end) == 31)
    }

    @Test("financialMonths end each month at the last instant of its last day")
    func financialMonthsEndAtLastInstant() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!

        let months = PayCycleService.financialMonths(count: 3, before: referenceDate, startDay: 10, calendar: calendar)

        for month in months {
            let nextStart = calendar.date(byAdding: .month, value: 1, to: month.start)!
            #expect(month.end == nextStart.addingTimeInterval(-0.001))
            #expect(calendar.component(.day, from: month.end) == 9)
        }
    }

    /// Havana's DST starts by skipping midnight (2026-03-08 00:00 doesn't exist), so that cycle
    /// starts at 01:00. Its end must still be the last instant of April 7, not 00:59 on April 8.
    @Test("a cycle starting on a skipped midnight still ends at the next day's start")
    func cycleEndIgnoresDSTSkippedMidnight() {
        var havana = Calendar(identifier: .gregorian)
        havana.timeZone = TimeZone(identifier: "America/Havana")!
        let now = havana.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))!
        let nextStart = havana.date(from: DateComponents(year: 2026, month: 4, day: 8))!

        let (start, end) = PayCycleService.currentFinancialMonth(startDay: 8, now: now, calendar: havana)

        #expect(havana.component(.hour, from: start) == 1)  // precondition: midnight was skipped
        #expect(end == nextStart.addingTimeInterval(-0.001))
    }

    @Test("financialMonths last month contains reference date")
    func financialMonthsContainsReferenceDate() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let startDay = 10

        let months = PayCycleService.financialMonths(count: 3, before: referenceDate, startDay: startDay, calendar: calendar)
        let lastMonth = months.last

        guard let lastMonth else { return #expect(Bool(false)) }
        #expect(referenceDate >= lastMonth.start && referenceDate <= lastMonth.end)
    }
}
