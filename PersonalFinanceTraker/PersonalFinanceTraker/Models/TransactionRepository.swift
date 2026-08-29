//  TransactionRepository.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

struct SearchFilters: Equatable, Sendable {
    var type: TransactionTypeFilter = .all
    var categories: Set<String> = []
    var dateRange: SearchDateRange? = nil
    var amountMin: Decimal? = nil
    var amountMax: Decimal? = nil
    var recurringOnly: Bool = false

    var isActive: Bool {
        type != .all || !categories.isEmpty || dateRange != nil || amountMin != nil || amountMax != nil || recurringOnly
    }
}

enum TransactionTypeFilter: String, CaseIterable, Equatable, Sendable {
    case all = "All"
    case income = "Income"
    case expense = "Expense"
}

enum SearchDateRange: Equatable, Sendable {
    case thisMonth, last3Months, thisYear
    case custom(from: Date, to: Date)

    var dateInterval: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisMonth:
            return (cal.date(from: cal.dateComponents([.year, .month], from: now))!, now)
        case .last3Months:
            return (cal.date(byAdding: .month, value: -3, to: now)!, now)
        case .thisYear:
            return (cal.date(from: cal.dateComponents([.year], from: now))!, now)
        case .custom(let from, let to):
            // Convert end date to end-of-day (start of next day) to include all transactions on that day
            let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
            return (from, endOfDay)
        }
    }

    var label: String {
        switch self {
        case .thisMonth: String(localized: "This month")
        case .last3Months: String(localized: "Last 3 months")
        case .thisYear: String(localized: "This year")
        case .custom: String(localized: "Custom")
        }
    }
}

protocol ITransactionRepository {
    // Transactions
    func fetchAll() async throws -> [TransactionSnapshot]
    func add(_ input: TransactionInput) async throws
    func addBatch(_ inputs: [TransactionInput]) async throws
    func delete(id: PersistentIdentifier) async throws
    func update(id: PersistentIdentifier, with input: TransactionInput) async throws
    func deleteAllTransactions() async throws

    // Categories
    func fetchCategories() async throws -> [CategorySnapshot]
    func addCategory(_ input: CategoryInput) async throws
    func deleteCategory(id: PersistentIdentifier) async throws

    // Goals
    func fetchGoals() async throws -> [GoalSnapshot]
    func addGoal(_ input: GoalInput) async throws
    func updateGoal(id: UUID, with input: GoalInput) async throws
    func deleteGoal(id: UUID) async throws

    // Recurrence rules
    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws
    func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot]
    func fetchAllRecurrenceRules() async throws -> [RecurrenceRuleSnapshot]
    func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot?
    func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws
    func closeRecurrenceRule(id: UUID, endDate: Date) async throws
    func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws
    func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws
    func deleteAllRecurrenceRules() async throws
    func linkTransactionsToRecurrenceRule(id: UUID, amount: Decimal, occurrenceDates: [Date]) async throws

    // Health snapshots
    func saveSnapshot(_ data: HealthScoreSnapshotData) async throws
    func fetchSnapshots(limit: Int) async throws -> [HealthScoreSnapshotData]

    // Forecast cache
    func fetchForecastCache() async throws -> DailyForecastCacheData?
    func saveForecastCache(_ data: DailyForecastCacheData) async throws

    // Receipt scan: learned merchant → category, keyed by ReceiptCategoryInferrer.normalize(merchant)
    func fetchMerchantCategoryMappings() async throws -> [String: UUID]
    func saveMerchantCategoryMapping(merchant: String, categoryId: UUID) async throws
}

extension SearchFilters {
    /// Bounds resolved once per filter pass; dateInterval does Calendar math
    func resolvedDateBounds() -> (start: Date, end: Date)? {
        dateRange?.dateInterval
    }

    /// True when the transaction passes every active filter. Pass precomputed
    /// bounds from resolvedDateBounds() when filtering many items.
    func matches(_ tx: TransactionSnapshot, dateBounds: (start: Date, end: Date)?) -> Bool {
        // Type filter: income (positive) or expense (negative)
        switch type {
        case .income:
            if tx.amount <= 0 { return false }
        case .expense:
            if tx.amount >= 0 { return false }
        case .all:
            break
        }

        // Category filter: if categories set is non-empty, must contain tx.category
        if !categories.isEmpty, !categories.contains(tx.category) {
            return false
        }

        // Date range filter: tx.timestamp must be within the interval
        if dateRange != nil, let (start, end) = dateBounds {
            guard tx.timestamp >= start && tx.timestamp < end else { return false }
        }

        // Amount bounds filter: check absolute value against min/max
        if let min = amountMin, abs(tx.amount) < min { return false }
        if let max = amountMax, abs(tx.amount) > max { return false }

        // Recurring filter: transaction must belong to a recurrence series
        if recurringOnly, tx.recurrenceRuleId == nil { return false }

        return true
    }

    /// Convenience one-argument form that computes bounds internally
    func matches(_ tx: TransactionSnapshot) -> Bool {
        matches(tx, dateBounds: resolvedDateBounds())
    }
}
