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
