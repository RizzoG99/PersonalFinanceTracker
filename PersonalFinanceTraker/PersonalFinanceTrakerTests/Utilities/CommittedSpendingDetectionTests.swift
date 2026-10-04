//  CommittedSpendingDetectionTests.swift
//  PersonalFinanceTraker
//
//  #188: whole-history fixed-expense detection, forecast-only payment matching, missed payments.

import Testing
import Foundation
@testable import PersonalFinanceTraker

struct CommittedSpendingDetectionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func input(_ note: String, _ amount: Decimal, _ date: Date, ruleId: UUID? = nil) -> TransactionInput {
        TransactionInput(timestamp: date, amount: amount, note: note, category: "Bills", currencyCode: "EUR", recurrenceRuleId: ruleId)
    }

    private func detect(_ inputs: [TransactionInput], today: Date, rules: [RecurrenceRuleSnapshot] = [], dismissed: [DismissedRecurrencePattern] = []) -> [RecurrenceSuggestion] {
        RecurrenceDetector.detect(in: inputs, existingRules: rules, dismissed: dismissed, today: today, calendar: calendar)
    }

    // MARK: - Detection

    @Test func monthNamesAreStrippedFromNotes() {
        #expect(RecurrenceDetector.normalizeNote("Affitto Ottobre 2026") == "affitto")
        #expect(RecurrenceDetector.normalizeNote("Rent - Sep.") == "rent")
        #expect(RecurrenceDetector.normalizeNote("Netflix.com") == "netflix com")
    }

    @Test func twoIdenticalPaymentsAreEnough() {
        let results = detect([
            input("Affitto settembre", -700, day(2026, 9, 1)),
            input("Affitto ottobre", -700, day(2026, 10, 1)),
        ], today: day(2026, 10, 4))
        #expect(results.count == 1)
        #expect(results.first?.amountsIdentical == true)
        #expect(results.first?.frequency == .monthly)
    }

    @Test func manualAndImportedSamePriceCountAsIdentical() {
        // Add form: Decimal(Double) → 8.99000000000000020…; CSV import: exact "8.99".
        let results = detect([
            input("Netflix", -Decimal(8.99), day(2026, 9, 3)),
            input("Netflix", Decimal(string: "-8.99")!, day(2026, 10, 3)),
        ], today: day(2026, 10, 4))
        #expect(results.count == 1)
        #expect(results.first?.amountsIdentical == true)
    }

    @Test func variableBillWithTimeOfDayDriftIsDetected() {
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = TimeZone(identifier: "Europe/Rome")!
        let f = ISO8601DateFormatter()
        let results = RecurrenceDetector.detect(in: [
            input("Electricity bill", -66, f.date(from: "2026-08-01T12:16:00Z")!),
            input("Electricity Bill", -62.5, f.date(from: "2026-09-01T12:12:00Z")!),
            input("Electricity bill", Decimal(-65.43), f.date(from: "2026-10-01T11:54:43Z")!),
        ], existingRules: [], today: f.date(from: "2026-10-04T13:00:00Z")!, calendar: rome)
        #expect(results.count == 1)
    }

    @Test func variableAmountsNeedThreePaymentsWithinTolerance() {
        let two = [input("Enel", -80, day(2026, 8, 10)), input("Enel", -88, day(2026, 9, 10))]
        #expect(detect(two, today: day(2026, 9, 20)).isEmpty)

        let three = two + [input("Enel", -84, day(2026, 10, 10))]
        let results = detect(three, today: day(2026, 10, 12))
        #expect(results.count == 1)
        #expect(results.first?.amountsIdentical == false)
        #expect(results.first?.amount == -84)   // median
    }

    @Test func amountsOutsideToleranceAreDifferentBills() {
        // Same note, two amounts 2× apart, each only twice: two separate identical-amount pairs.
        let results = detect([
            input("Loan", -100, day(2026, 8, 5)), input("Loan", -100, day(2026, 9, 5)),
            input("Loan", -200, day(2026, 8, 5)), input("Loan", -200, day(2026, 9, 5)),
        ], today: day(2026, 9, 10))
        #expect(Set(results.map(\.amount)) == [-100, -200])
    }

    @Test func incomeGeneratedRowsAndEmptyNotesAreIgnored() {
        let ruleId = UUID()
        let results = detect([
            input("Salary", 2000, day(2026, 8, 27)), input("Salary", 2000, day(2026, 9, 27)),
            input("Gym", -40, day(2026, 8, 3), ruleId: ruleId), input("Gym", -40, day(2026, 9, 3), ruleId: ruleId),
            input("", -5, day(2026, 8, 1)), input("", -5, day(2026, 9, 1)),
        ], today: day(2026, 9, 28))
        #expect(results.isEmpty)
    }

    @Test func irregularCadenceIsNotSuggested() {
        // A single ~70-day gap would fit "every 10 weeks" — outside V1's allow-list (#196).
        let results = detect([
            input("Barber", -20, day(2026, 6, 1)), input("Barber", -20, day(2026, 8, 10)),
        ], today: day(2026, 8, 15))
        #expect(results.isEmpty)
    }

    @Test func cancelledSubscriptionIsNotSuggested() {
        let inputs = [input("Gym", -40, day(2025, 1, 3)), input("Gym", -40, day(2025, 2, 3)), input("Gym", -40, day(2025, 3, 3))]
        #expect(detect(inputs, today: day(2026, 10, 4)).isEmpty)
        #expect(detect(inputs, today: day(2025, 3, 20)).count == 1)
    }

    @Test func dismissedAndExistingRulePatternsAreSkipped() {
        let inputs = [input("Netflix", -12.99, day(2026, 8, 5)), input("Netflix", -12.99, day(2026, 9, 5))]
        let today = day(2026, 9, 10)
        let suggestion = try! #require(detect(inputs, today: today).first)

        let dismissed = [RecurrenceDetector.dismissalPattern(for: suggestion)]
        #expect(detect(inputs, today: today, dismissed: dismissed).isEmpty)

        // A rule with a slightly different amount (price rise within 15 %) still covers it.
        let rule = RecurrenceRuleSnapshot.test(startDate: day(2026, 1, 5), amount: -13.99, note: "NETFLIX", category: "Fun")
        #expect(detect(inputs, today: today, rules: [rule]).isEmpty)
    }

    @Test func driftingSeriesIsSuggestedAndAnchoredOnLatestPayment() {
        // Anchored on the first payment (the 26th), the 25 Sep payment read as "early" and a
        // phantom 26 Sep occurrence went unpaid, so the series was dropped as stopped.
        let results = detect([
            input("Gym membership", -39.99, day(2026, 8, 26)),
            input("Gym Membership", -39.99, day(2026, 9, 25)),
        ], today: day(2026, 10, 4))
        let suggestion = try! #require(results.first)
        #expect(suggestion.nextDate == day(2026, 10, 25))
        let rule = suggestion.ruleInput(autoRecord: false)
        #expect(rule.startDate == day(2026, 9, 25))
        #expect(rule.lastMaterializedDate == day(2026, 9, 25))
    }

    @Test func confirmedRuleIsAnchoredOnLatestPayment() {
        let suggestion = try! #require(detect([
            input("Rent", -700, day(2026, 8, 1)), input("Rent", -700, day(2026, 9, 1)),
        ], today: day(2026, 9, 3)).first)
        let rule = suggestion.ruleInput(autoRecord: false)
        #expect(rule.startDate == day(2026, 9, 1))
        #expect(rule.lastMaterializedDate == day(2026, 9, 1))
        #expect(rule.autoRecord == false)
        #expect(suggestion.ruleInput(autoRecord: true).autoRecord == true)
    }

    // MARK: - Forecast-only matching

    private func forecastRule(cursor: Date, amount: Decimal = -80) -> RecurrenceRuleSnapshot {
        .test(startDate: day(2026, 1, 10), lastMaterializedDate: cursor, autoRecord: false, amount: amount, note: "Enel", category: "Bills")
    }

    @Test func paymentWithinWindowAdvancesCursorAndAmount() {
        let rule = forecastRule(cursor: day(2026, 9, 10))
        let paid = RecurrenceDetector.paidThrough(
            rule: rule,
            transactions: [.test(timestamp: day(2026, 10, 13), amount: -86, note: "ENEL ottobre", category: "Bills")],
            today: day(2026, 10, 14),
            calendar: calendar
        )
        #expect(paid?.cursor == day(2026, 10, 10))
        #expect(paid?.amount == -86)
    }

    @Test func earlyPaymentCountsBeforeTheDueDate() {
        let rule = forecastRule(cursor: day(2026, 9, 10))
        let paid = RecurrenceDetector.paidThrough(
            rule: rule,
            transactions: [.test(timestamp: day(2026, 10, 6), amount: -80, note: "Enel", category: "Bills")],
            today: day(2026, 10, 6),
            calendar: calendar
        )
        #expect(paid?.cursor == day(2026, 10, 10))
    }

    @Test func wrongNoteAmountOrDateDoesNotMatch() {
        let rule = forecastRule(cursor: day(2026, 9, 10))
        let paid = RecurrenceDetector.paidThrough(
            rule: rule,
            transactions: [
                .test(timestamp: day(2026, 10, 10), amount: -80, note: "Coop", category: "Food"),
                .test(timestamp: day(2026, 10, 10), amount: -200, note: "Enel", category: "Bills"),
                .test(timestamp: day(2026, 10, 25), amount: -80, note: "Enel", category: "Bills"),
            ],
            today: day(2026, 10, 26),
            calendar: calendar
        )
        #expect(paid == nil)
    }

    @Test func missedPaymentIsReportedOnlyAfterTheWindowCloses() {
        let rule = forecastRule(cursor: day(2026, 9, 10))
        #expect(RecurrenceDetector.missedOccurrence(rule: rule, today: day(2026, 10, 14), calendar: calendar) == nil)
        #expect(RecurrenceDetector.missedOccurrence(rule: rule, today: day(2026, 10, 20), calendar: calendar) == day(2026, 10, 10))

        let autoRecord = RecurrenceRuleSnapshot.test(startDate: day(2026, 1, 10), lastMaterializedDate: day(2026, 9, 10), amount: -80, note: "Enel", category: "Bills")
        #expect(RecurrenceDetector.missedOccurrence(rule: autoRecord, today: day(2026, 10, 20), calendar: calendar) == nil)
    }

    // MARK: - Materializer

    @Test func confirmedAutoRecordRuleDoesNotRecordThePaymentItCameFrom() async throws {
        // Old anchoring: startDate on the first payment's time (14:00), cursor on the last one's
        // (13:54) → the materializer inserted a duplicate "14:00" occurrence the same day.
        let first = day(2026, 9, 3).addingTimeInterval(2 * 3600)
        let last = day(2026, 10, 3).addingTimeInterval(2 * 3600 - 317)
        let suggestion = try #require(detect([
            input("Netflix", -8.99, first), input("Netflix", -8.99, last),
        ], today: day(2026, 10, 4)).first)
        let ruleInput = suggestion.ruleInput(autoRecord: true)
        let repo = MockTransactionRepository()
        repo.stubbedRecurrenceRules = [.test(
            startDate: ruleInput.startDate, lastMaterializedDate: ruleInput.lastMaterializedDate,
            autoRecord: ruleInput.autoRecord, amount: ruleInput.amount, note: ruleInput.note, category: "Fun"
        )]

        try await RecurrenceMaterializationService().materialize(using: repo, today: day(2026, 10, 4), calendar: calendar)

        #expect(repo.materializeOccurrencesCalls.isEmpty)
    }

    @Test func materializerMatchesForecastOnlyRulesInsteadOfInserting() async throws {
        let repo = MockTransactionRepository()
        let rule = forecastRule(cursor: day(2026, 9, 10))
        repo.stubbedRecurrenceRules = [rule]
        repo.stubbedTransactions = [.test(timestamp: day(2026, 10, 11), amount: -82, note: "Enel", category: "Bills")]

        try await RecurrenceMaterializationService().materialize(using: repo, today: day(2026, 10, 12), calendar: calendar)

        #expect(repo.materializeOccurrencesCalls.isEmpty)
        #expect(repo.advanceRecurrenceRuleCalls.count == 1)
        #expect(repo.advanceRecurrenceRuleCalls.first?.cursor == day(2026, 10, 10))
        #expect(repo.advanceRecurrenceRuleCalls.first?.amount == -82)
    }
}
