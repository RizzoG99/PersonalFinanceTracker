import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceOccurrenceCalculatorTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func monthlyRuleStartingJan31ClampsToMonthEnd() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 31),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 4, 30),
            calendar: calendar
        )
        #expect(dates == [date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)])
    }

    @Test func monthlyClampDoesNotDriftTheFollowingMonth() {
        // Feb 28 (clamped from Jan 31) must not become the new anchor day for March.
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 31),
            ruleEndDate: nil,
            since: date(2026, 2, 28),
            through: date(2026, 3, 31),
            calendar: calendar
        )
        #expect(dates == [date(2026, 3, 31)])
    }

    @Test func yearlyLeapDayClampsToFeb28OnNonLeapYear() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .yearly,
            interval: 1,
            startDate: date(2024, 2, 29),
            ruleEndDate: nil,
            since: nil,
            through: date(2025, 12, 31),
            calendar: calendar
        )
        #expect(dates == [date(2024, 2, 29), date(2025, 2, 28)])
    }

    @Test func weeklyEveryTwoWeeks() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .weekly,
            interval: 2,
            startDate: date(2026, 3, 2),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(dates == [date(2026, 3, 2), date(2026, 3, 16), date(2026, 3, 30)])
    }

    @Test func monthlyEveryThreeMonthsWithClamping() {
        // interval > 2, combined with month-end clamping, to cover UI intervals beyond weekly/2.
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 3,
            startDate: date(2026, 1, 31),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 10, 31),
            calendar: calendar
        )
        #expect(dates == [date(2026, 1, 31), date(2026, 4, 30), date(2026, 7, 31), date(2026, 10, 31)])
    }

    @Test func sinceCursorExcludesAlreadyMaterializedOccurrence() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            ruleEndDate: nil,
            since: date(2026, 2, 1),
            through: date(2026, 3, 1),
            calendar: calendar
        )
        #expect(dates == [date(2026, 3, 1)])
    }

    @Test func ruleEndDateStopsGeneratingFurtherOccurrences() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            ruleEndDate: date(2026, 1, 15),
            since: nil,
            through: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(dates == [date(2026, 1, 1)])
    }

    @Test func noOccurrencesWhenThroughIsBeforeStartDate() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 5, 1),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(dates.isEmpty)
    }
}
