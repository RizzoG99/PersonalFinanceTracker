import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceRuleTests {
    private func makeRule(endDate: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .yearly,
            interval: 1,
            startDate: .now,
            endDate: endDate,
            amount: -10,
            note: "Test",
            category: "Food",
            currencyCode: "EUR"
        )
    }

    @Test func recurrenceFrequencyDecodesRawValue() {
        #expect(makeRule().recurrenceFrequency == .yearly)
    }

    @Test func isActiveWhenEndDateIsNil() {
        #expect(makeRule().isActive(asOf: .now) == true)
    }

    @Test func isActiveWhenEndDateIsInTheFuture() {
        let future = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        #expect(makeRule(endDate: future).isActive(asOf: .now) == true)
    }

    @Test func notActiveWhenEndDateIsInThePast() {
        let past = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        #expect(makeRule(endDate: past).isActive(asOf: .now) == false)
    }
}
