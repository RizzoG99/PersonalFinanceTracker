import Foundation
import SwiftData

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
    /// `PersistentIdentifier` doesn't survive a JSON round-trip, so a restore can only
    /// relink each backed-up row to whatever `CategoryModel` currently exists in the store,
    /// matched by name + type (income/expense categories can share a name). Without this,
    /// every transaction and recurrence rule restored from a backup loses its category link,
    /// and every icon that isn't in `CategoryInfo`'s seeded keyword table falls back to the
    /// generic glyph (#153) — permanently, since there's no other path that relinks them.
    private static func categoryPersistentIds(for categories: [CategorySnapshot]) -> [String: PersistentIdentifier] {
        Dictionary(
            categories.map { ("\($0.name)#\($0.type)", $0.persistentId) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func categoryKey(name: String, amount: Decimal) -> String {
        "\(name)#\((amount < 0 ? TransactionType.expense : TransactionType.income).rawValue)"
    }

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

    static func makeTransactionInputs(from backups: [BackupTransaction], categories: [CategorySnapshot] = []) -> [TransactionInput] {
        let byKey = categoryPersistentIds(for: categories)
        return backups.map {
            TransactionInput(
                timestamp: $0.timestamp,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId,
                categoryPersistentId: byKey[categoryKey(name: $0.category, amount: $0.amount)],
                recurrenceRuleId: $0.recurrenceRuleId
            )
        }
    }

    static func makeRecurrenceRuleInputs(from backups: [BackupRecurrenceRule], categories: [CategorySnapshot] = []) -> [RecurrenceRuleInput] {
        let byKey = categoryPersistentIds(for: categories)
        return backups.map {
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
                goalId: $0.goalId,
                categoryPersistentId: byKey[categoryKey(name: $0.category, amount: $0.amount)]
            )
        }
    }
}
