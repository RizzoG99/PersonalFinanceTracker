import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

struct TransactionActorRecurrenceTests {
    private func makeActor() -> TransactionActor {
        let schema = Schema([TransactionModel.self, CategoryModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return TransactionActor(modelContainer: container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func ruleInput(startDate: Date) -> RecurrenceRuleInput {
        RecurrenceRuleInput(frequency: .monthly, interval: 1, startDate: startDate, amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR")
    }

    @Test func addAndFetchActiveRecurrenceRule() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let active = try await actor.fetchActiveRecurrenceRules()
        #expect(active.count == 1)
        #expect(active[0].id == input.id)
        #expect(active[0].frequency == .monthly)
    }

    @Test func fetchActiveExcludesRulesClosedInThePast() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)
        try await actor.closeRecurrenceRule(id: input.id, endDate: date(2026, 1, 15))

        // fetchActiveRecurrenceRules compares against "now", so a rule closed in 2026-01
        // stays excluded as long as the test runs after that date.
        let active = try await actor.fetchActiveRecurrenceRules()
        #expect(active.isEmpty)
    }

    @Test func fetchRecurrenceRuleById() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let fetched = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(fetched?.id == input.id)
        #expect(try await actor.fetchRecurrenceRule(id: UUID()) == nil)
    }

    @Test func materializeOccurrencesInsertsTaggedTransactionsAndAdvancesCursor() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let txInputs = [
            TransactionInput(timestamp: date(2026, 1, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id),
            TransactionInput(timestamp: date(2026, 2, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id)
        ]
        try await actor.materializeOccurrences(ruleId: input.id, inputs: txInputs, newCursor: date(2026, 2, 1))

        let all = try await actor.fetchAll()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.recurrenceRuleId == input.id })

        let rule = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(rule?.lastMaterializedDate == date(2026, 2, 1))
    }

    @Test func updateRecurrenceRuleMutatesTemplateInPlace() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let updated = RecurrenceRuleInput(id: input.id, frequency: .monthly, interval: 1, startDate: input.startDate, amount: -1500, note: "Rent (increased)", category: "Housing", currencyCode: "EUR")
        try await actor.updateRecurrenceRule(id: input.id, with: updated)

        let rule = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(rule?.amount == -1500)
        #expect(rule?.note == "Rent (increased)")
        #expect(rule?.startDate == input.startDate) // unchanged — v1 edit UI never changes cadence
    }

    @Test func deleteOccurrencesRemovesRowsAndResetsCursor() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)
        try await actor.materializeOccurrences(
            ruleId: input.id,
            inputs: [
                TransactionInput(timestamp: date(2026, 1, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id),
                TransactionInput(timestamp: date(2026, 2, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id)
            ],
            newCursor: date(2026, 2, 1)
        )

        try await actor.deleteOccurrences(recurrenceRuleId: input.id, from: date(2026, 2, 1))

        let all = try await actor.fetchAll()
        #expect(all.count == 1) // January row survives, February row (>= cutoff) is removed
        #expect(all[0].timestamp == date(2026, 1, 1))

        let rule = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(rule!.lastMaterializedDate! < date(2026, 2, 1))
    }
}
