import Testing
import Foundation
@testable import PersonalFinanceTraker

struct BackupModelsTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func transactionRoundTripsThroughBackupTransaction() {
        let ruleId = UUID()
        let snapshot = TransactionSnapshot.test(
            timestamp: date(2026, 1, 5),
            amount: -42.50,
            note: "Lunch",
            category: "Food",
            currencyCode: "EUR",
            recurrenceRuleId: ruleId
        )

        let backups = BackupMapper.makeTransactions(from: [snapshot])
        #expect(backups.count == 1)
        #expect(backups[0].amount == -42.50)
        #expect(backups[0].note == "Lunch")
        #expect(backups[0].recurrenceRuleId == ruleId)

        let inputs = BackupMapper.makeTransactionInputs(from: backups)
        #expect(inputs.count == 1)
        #expect(inputs[0].amount == -42.50)
        #expect(inputs[0].category == "Food")
        #expect(inputs[0].recurrenceRuleId == ruleId)
    }

    @Test func recurrenceRuleRoundTripsThroughBackupRecurrenceRule() {
        let endDate = date(2026, 12, 31)
        let lastMaterializedDate = date(2026, 7, 1)
        let snapshot = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            endDate: endDate,
            lastMaterializedDate: lastMaterializedDate,
            amount: -1200,
            category: "Housing"
        )

        let backups = BackupMapper.makeRecurrenceRules(from: [snapshot])
        #expect(backups.count == 1)
        #expect(backups[0].frequency == RecurrenceFrequency.monthly)
        #expect(backups[0].amount == -1200)
        #expect(backups[0].endDate == endDate)
        #expect(backups[0].lastMaterializedDate == lastMaterializedDate)

        let inputs = BackupMapper.makeRecurrenceRuleInputs(from: backups)
        #expect(inputs.count == 1)
        #expect(inputs[0].id == snapshot.id)
        #expect(inputs[0].frequency == RecurrenceFrequency.monthly)
        #expect(inputs[0].endDate == endDate)
        #expect(inputs[0].lastMaterializedDate == lastMaterializedDate)
    }

    @Test func backupPayloadEncodesAndDecodesAsJSON() throws {
        let endDate = date(2026, 12, 31)
        let lastMaterializedDate = date(2026, 7, 1)
        let payload = BackupPayload(
            version: 1,
            createdAt: date(2026, 1, 1),
            transactions: [BackupTransaction(timestamp: date(2026, 1, 1), amount: -10, note: "A", category: "Food", currencyCode: "EUR", goalId: nil, recurrenceRuleId: nil)],
            recurrenceRules: [BackupRecurrenceRule(id: UUID(), frequency: .monthly, interval: 1, startDate: date(2026, 1, 1), endDate: endDate, lastMaterializedDate: lastMaterializedDate, amount: -1200, note: "", category: "Housing", currencyCode: "EUR", goalId: nil)]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)

        #expect(decoded.transactions.count == 1)
        #expect(decoded.transactions[0].note == "A")
        #expect(decoded.version == 1)
        #expect(decoded.recurrenceRules.count == 1)
        #expect(decoded.recurrenceRules[0].endDate == endDate)
        #expect(decoded.recurrenceRules[0].lastMaterializedDate == lastMaterializedDate)
    }
}
