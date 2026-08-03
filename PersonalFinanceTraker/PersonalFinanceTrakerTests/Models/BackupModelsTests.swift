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
            category: "Food",
            note: "Lunch",
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
        let snapshot = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            amount: -1200,
            category: "Housing"
        )

        let backups = BackupMapper.makeRecurrenceRules(from: [snapshot])
        #expect(backups.count == 1)
        #expect(backups[0].frequency == .monthly)
        #expect(backups[0].amount == -1200)

        let inputs = BackupMapper.makeRecurrenceRuleInputs(from: backups)
        #expect(inputs.count == 1)
        #expect(inputs[0].id == snapshot.id)
        #expect(inputs[0].frequency == .monthly)
    }

    @Test func backupPayloadEncodesAndDecodesAsJSON() throws {
        let payload = BackupPayload(
            version: 1,
            createdAt: date(2026, 1, 1),
            transactions: [BackupTransaction(timestamp: date(2026, 1, 1), amount: -10, note: "A", category: "Food", currencyCode: "EUR", goalId: nil, recurrenceRuleId: nil)],
            recurrenceRules: []
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
    }
}
