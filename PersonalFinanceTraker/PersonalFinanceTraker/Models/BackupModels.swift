import Foundation

struct BackupTransaction: Codable, Sendable {
    let timestamp: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let recurrenceRuleId: UUID?
}

struct BackupRecurrenceRule: Codable, Sendable {
    let id: UUID
    let frequency: RecurrenceFrequency
    let interval: Int
    let startDate: Date
    let endDate: Date?
    let lastMaterializedDate: Date?
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
}

struct BackupPayload: Codable, Sendable {
    let version: Int
    let createdAt: Date
    let transactions: [BackupTransaction]
    let recurrenceRules: [BackupRecurrenceRule]
}

enum BackupMapper {
    static func makeTransactions(from snapshots: [TransactionSnapshot]) -> [BackupTransaction] {
        snapshots.map {
            BackupTransaction(
                timestamp: $0.timestamp,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId,
                recurrenceRuleId: $0.recurrenceRuleId
            )
        }
    }

    static func makeRecurrenceRules(from snapshots: [RecurrenceRuleSnapshot]) -> [BackupRecurrenceRule] {
        snapshots.map {
            BackupRecurrenceRule(
                id: $0.id,
                frequency: $0.frequency,
                interval: $0.interval,
                startDate: $0.startDate,
                endDate: $0.endDate,
                lastMaterializedDate: $0.lastMaterializedDate,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId
            )
        }
    }

    static func makeTransactionInputs(from backups: [BackupTransaction]) -> [TransactionInput] {
        backups.map {
            TransactionInput(
                timestamp: $0.timestamp,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId,
                recurrenceRuleId: $0.recurrenceRuleId
            )
        }
    }

    static func makeRecurrenceRuleInputs(from backups: [BackupRecurrenceRule]) -> [RecurrenceRuleInput] {
        backups.map {
            RecurrenceRuleInput(
                id: $0.id,
                frequency: $0.frequency,
                interval: $0.interval,
                startDate: $0.startDate,
                endDate: $0.endDate,
                lastMaterializedDate: $0.lastMaterializedDate,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId
            )
        }
    }
}
