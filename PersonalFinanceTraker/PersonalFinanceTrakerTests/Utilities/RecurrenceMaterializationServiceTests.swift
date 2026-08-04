import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceMaterializationServiceTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func materializesDueOccurrencesAndAdvancesCursor() async throws {
        let mock = MockTransactionRepository()
        mock.stubbedRecurrenceRules = [
            .test(startDate: date(2026, 1, 1), amount: -1200, category: "Rent")
        ]
        let service = RecurrenceMaterializationService()

        try await service.materialize(using: mock, today: date(2026, 3, 1))

        #expect(mock.materializeOccurrencesCalls.count == 1)
        let call = mock.materializeOccurrencesCalls[0]
        #expect(call.inputs.map(\.timestamp) == [date(2026, 1, 1), date(2026, 2, 1), date(2026, 3, 1)])
        #expect(call.inputs.allSatisfy { $0.recurrenceRuleId == call.ruleId })
        #expect(call.newCursor == date(2026, 3, 1))
    }

    @Test func skipsRuleWithNoDueOccurrencesYet() async throws {
        let mock = MockTransactionRepository()
        mock.stubbedRecurrenceRules = [
            .test(startDate: date(2026, 5, 1), amount: -1200, category: "Rent")
        ]
        let service = RecurrenceMaterializationService()

        try await service.materialize(using: mock, today: date(2026, 3, 1))

        #expect(mock.materializeOccurrencesCalls.isEmpty)
    }

    @Test func concurrentCallsOnlyFetchRulesOnce() async throws {
        let mock = MockTransactionRepository()
        mock.fetchActiveRecurrenceRulesDelayNanoseconds = 50_000_000 // 50ms — forces overlap
        mock.stubbedRecurrenceRules = [
            .test(startDate: date(2026, 1, 1), amount: -1200, category: "Rent")
        ]
        let service = RecurrenceMaterializationService()

        async let first: Void = service.materialize(using: mock, today: date(2026, 3, 1))
        async let second: Void = service.materialize(using: mock, today: date(2026, 3, 1))
        _ = try await (first, second)

        #expect(mock.fetchActiveRecurrenceRulesCallCount == 1)
    }
}
