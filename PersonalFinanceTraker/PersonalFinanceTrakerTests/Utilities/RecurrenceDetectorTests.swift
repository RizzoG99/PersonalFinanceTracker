//  RecurrenceDetectorTests.swift
//  PersonalFinanceTraker

import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceDetectorTests {
    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Test Helpers

    private func makeTransactionInput(
        note: String,
        amount: Decimal,
        timestamp: Date
    ) -> TransactionInput {
        TransactionInput(
            timestamp: timestamp,
            amount: amount,
            note: note,
            category: "Food",
            currencyCode: "EUR",
            goalId: nil,
            categoryPersistentId: nil,
            recurrenceRuleId: nil
        )
    }

    private func makeRecurrenceRuleSnapshot(
        note: String,
        amount: Decimal,
        frequency: RecurrenceFrequency
    ) -> RecurrenceRuleSnapshot {
        let fixedDate = dateAtMidnight(2020, 1, 1)
        return RecurrenceRuleSnapshot.test(
            frequency: frequency,
            interval: 1,
            startDate: fixedDate,
            endDate: nil,
            lastMaterializedDate: nil,
            amount: amount,
            note: note,
            category: "Food",
            currencyCode: "EUR",
            goalId: nil
        )
    }

    private func dateAtMidnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)!
    }

    // MARK: - Test Cases

    @Test func nextDateMustBeAfterToday() {
        // Rows ending 6 months before today should produce nextDate after today
        let today = dateAtMidnight(2026, 8, 15)
        let baseDate = dateAtMidnight(2026, 2, 15)
        var inputs: [TransactionInput] = []

        for month in 0..<3 {
            let date = calendar.date(byAdding: .month, value: month, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Netflix", amount: -10, timestamp: date))
        }
        // Last row is April 15; today is August 15

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: today, calendar: calendar)

        #expect(results.count == 1)
        let suggestion = results[0]
        // nextDate must be strictly after today (August 15), so it should be in September or later
        #expect(suggestion.nextDate > today)
    }

    @Test func monthlyPattern12Rows() {
        let baseDate = dateAtMidnight(2026, 1, 15)
        var inputs: [TransactionInput] = []

        for month in 0..<12 {
            let date = calendar.date(byAdding: .month, value: month, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Netflix", amount: -10, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
        let suggestion = results[0]
        #expect(suggestion.frequency == .monthly)
        #expect(suggestion.interval == 1)
        #expect(suggestion.amount == -10)
        #expect(suggestion.occurrenceCount == 12)

        // nextDate should be one month after the last row
        let expectedNextDate = calendar.date(byAdding: .month, value: 12, to: baseDate)!
        #expect(suggestion.nextDate == expectedNextDate)
    }

    @Test func differentAmounts() {
        let baseDate = dateAtMidnight(2026, 1, 15)
        let inputs = [
            makeTransactionInput(note: "Netflix", amount: -10, timestamp: baseDate),
            makeTransactionInput(note: "Netflix", amount: -15, timestamp: calendar.date(byAdding: .month, value: 1, to: baseDate)!),
            makeTransactionInput(note: "Netflix", amount: -10, timestamp: calendar.date(byAdding: .month, value: 2, to: baseDate)!),
        ]

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 0)
    }

    @Test func biweeklyPattern() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        var inputs: [TransactionInput] = []

        for i in 0..<5 {
            let date = calendar.date(byAdding: .day, value: i * 14, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Paycheck", amount: 2000, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
        let suggestion = results[0]
        #expect(suggestion.frequency == .weekly)
        #expect(suggestion.interval == 2)
        #expect(suggestion.occurrenceCount == 5)
    }

    @Test func irregularGaps() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        let inputs = [
            makeTransactionInput(note: "Irregular", amount: -50, timestamp: baseDate),
            makeTransactionInput(note: "Irregular", amount: -50, timestamp: calendar.date(byAdding: .day, value: 5, to: baseDate)!),
            makeTransactionInput(note: "Irregular", amount: -50, timestamp: calendar.date(byAdding: .day, value: 35, to: baseDate)!),
            makeTransactionInput(note: "Irregular", amount: -50, timestamp: calendar.date(byAdding: .day, value: 47, to: baseDate)!),
        ]

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 0)
    }

    @Test func onlyTwoOccurrences() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        let inputs = [
            makeTransactionInput(note: "Test", amount: -100, timestamp: baseDate),
            makeTransactionInput(note: "Test", amount: -100, timestamp: calendar.date(byAdding: .month, value: 1, to: baseDate)!),
        ]

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 0)
    }

    @Test func filteredByExistingRule() {
        let baseDate = dateAtMidnight(2026, 1, 15)
        var inputs: [TransactionInput] = []

        for month in 0..<6 {
            let date = calendar.date(byAdding: .month, value: month, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Netflix", amount: -10, timestamp: date))
        }

        let existingRule = makeRecurrenceRuleSnapshot(
            note: "netflix",  // Different case, should normalize to same
            amount: -10,
            frequency: .monthly
        )

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [existingRule], today: baseDate, calendar: calendar)

        #expect(results.count == 0)
    }

    @Test func sameGroupWithEmptyRules() {
        let baseDate = dateAtMidnight(2026, 1, 15)
        var inputs: [TransactionInput] = []

        for month in 0..<6 {
            let date = calendar.date(byAdding: .month, value: month, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Netflix", amount: -10, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
    }

    @Test func monthEndClamping() {
        // Jan 31 -> Feb 28 -> Mar 31 -> Apr 30 pattern
        let jan31 = dateAtMidnight(2026, 1, 31)
        let feb28 = dateAtMidnight(2026, 2, 28)
        let mar31 = dateAtMidnight(2026, 3, 31)
        let apr30 = dateAtMidnight(2026, 4, 30)

        let inputs = [
            makeTransactionInput(note: "Bill", amount: -100, timestamp: jan31),
            makeTransactionInput(note: "Bill", amount: -100, timestamp: feb28),
            makeTransactionInput(note: "Bill", amount: -100, timestamp: mar31),
            makeTransactionInput(note: "Bill", amount: -100, timestamp: apr30),
        ]

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: apr30, calendar: calendar)

        #expect(results.count == 1)
        let suggestion = results[0]
        #expect(suggestion.frequency == .monthly)
        #expect(suggestion.interval == 1)
        #expect(suggestion.occurrenceCount == 4)
    }

    @Test func noteNormalizationGrouping() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        var inputs: [TransactionInput] = []

        let notes = ["NETFLIX 05/26", "Netflix 06/26", "netflix 07/26"]
        for (i, note) in notes.enumerated() {
            let date = calendar.date(byAdding: .month, value: i, to: baseDate)!
            inputs.append(makeTransactionInput(note: note, amount: -12.99, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        // All three should group together with normalized note
        #expect(results.count == 1)
        #expect(results[0].occurrenceCount == 3)
        // With equal counts, should return lexicographically smallest: "NETFLIX 05/26"
        #expect(results[0].note == "NETFLIX 05/26")
    }

    @Test func yearlyPattern() {
        let base = dateAtMidnight(2024, 6, 15)
        let year2 = dateAtMidnight(2025, 6, 15)
        let year3 = dateAtMidnight(2026, 6, 15)

        let inputs = [
            makeTransactionInput(note: "Annual Fee", amount: -50, timestamp: base),
            makeTransactionInput(note: "Annual Fee", amount: -50, timestamp: year2),
            makeTransactionInput(note: "Annual Fee", amount: -50, timestamp: year3),
        ]

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: year3, calendar: calendar)

        #expect(results.count == 1)
        let suggestion = results[0]
        #expect(suggestion.frequency == .yearly)
        #expect(suggestion.interval == 1)
        #expect(suggestion.occurrenceCount == 3)
    }

    @Test func sortingByOccurrenceCount() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        var inputs: [TransactionInput] = []

        // Create 3 monthly netflix entries
        for i in 0..<3 {
            let date = calendar.date(byAdding: .month, value: i, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Netflix", amount: -12, timestamp: date))
        }

        // Create 6 monthly spotify entries
        for i in 0..<6 {
            let date = calendar.date(byAdding: .month, value: i, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Spotify", amount: -10, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 2)
        // Spotify should be first (6 occurrences > 3 occurrences)
        #expect(results[0].note.lowercased().contains("spotify"))
        #expect(results[0].occurrenceCount == 6)
        #expect(results[1].note.lowercased().contains("netflix"))
        #expect(results[1].occurrenceCount == 3)
    }

    @Test func mostCommonNote() {
        let baseDate = dateAtMidnight(2026, 1, 15)
        var inputs: [TransactionInput] = []

        // Mix of different notes that normalize to the same
        let notes = ["Netflix", "netflix", "NETFLIX"]
        for (i, note) in notes.enumerated() {
            let date = calendar.date(byAdding: .month, value: i, to: baseDate)!
            inputs.append(makeTransactionInput(note: note, amount: -10, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
        // With equal counts, should return lexicographically smallest: "NETFLIX"
        #expect(results[0].note == "NETFLIX")
    }

    @Test func weeklyInterval1() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        var inputs: [TransactionInput] = []

        for i in 0..<4 {
            let date = calendar.date(byAdding: .day, value: i * 7, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Weekly", amount: -50, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
        #expect(results[0].frequency == .weekly)
        #expect(results[0].interval == 1)
    }

    @Test func bimonthly60Days() {
        let baseDate = dateAtMidnight(2026, 1, 1)
        var inputs: [TransactionInput] = []

        for i in 0..<4 {
            let date = calendar.date(byAdding: .day, value: i * 60, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Bimonthly", amount: -100, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
        #expect(results[0].frequency == .monthly)
        #expect(results[0].interval == 2)
    }

    @Test func trimonthly91Days() {
        // 91-day gap: monthly n = round(91/30.4) = 3, expected 91.2, error 0.2%
        // Weekly n = round(91/7) = 13, expected 91, error 0%
        // Monthly wins because it's coarser (calendar-anchored beats day-of-week-anchored)
        let baseDate = dateAtMidnight(2026, 1, 1)
        var inputs: [TransactionInput] = []

        for i in 0..<4 {
            let date = calendar.date(byAdding: .day, value: i * 91, to: baseDate)!
            inputs.append(makeTransactionInput(note: "Quarterly", amount: -150, timestamp: date))
        }

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: baseDate, calendar: calendar)

        #expect(results.count == 1)
        #expect(results[0].frequency == .monthly)
        #expect(results[0].interval == 3)
    }

    @Test func yearlyCorrectly365Days() {
        // Verify yearly is detected correctly and not confused with weekly 52
        let baseDate = dateAtMidnight(2024, 6, 15)
        let year2 = dateAtMidnight(2025, 6, 15)
        let year3 = dateAtMidnight(2026, 6, 15)
        let year4 = dateAtMidnight(2027, 6, 15)

        let inputs = [
            makeTransactionInput(note: "Annual", amount: -300, timestamp: baseDate),
            makeTransactionInput(note: "Annual", amount: -300, timestamp: year2),
            makeTransactionInput(note: "Annual", amount: -300, timestamp: year3),
            makeTransactionInput(note: "Annual", amount: -300, timestamp: year4),
        ]

        let results = RecurrenceDetector.detect(in: inputs, existingRules: [], today: year4, calendar: calendar)

        #expect(results.count == 1)
        // Must be yearly, not weekly 52
        #expect(results[0].frequency == .yearly)
        #expect(results[0].interval == 1)
    }
}
