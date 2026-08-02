import Testing
import Foundation
import SwiftData
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

struct TransactionSnapshotRecurrenceTests {
    @Test func snapshotCarriesRecurrenceRuleIdFromModel() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: TransactionModel.self, configurations: config)
        let ctx = ModelContext(container)
        let ruleId = UUID()
        let model = TransactionModel(
            timestamp: .now, amount: -10, note: "Rent", category: "Housing",
            currencyCode: "EUR", goalId: nil, recurrenceRuleId: ruleId
        )
        ctx.insert(model)
        try! ctx.save()

        #expect(TransactionSnapshot(model).recurrenceRuleId == ruleId)
    }
}
