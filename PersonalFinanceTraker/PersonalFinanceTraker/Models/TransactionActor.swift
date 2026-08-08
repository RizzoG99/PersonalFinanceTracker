//  TransactionActor.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData
import WidgetKit

@ModelActor
actor TransactionActor: ITransactionRepository {

    // MARK: Transactions

    func fetchAll() async throws -> [TransactionSnapshot] {
        let desc = FetchDescriptor<TransactionModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(desc).map(TransactionSnapshot.init)
    }

    func add(_ input: TransactionInput) async throws {
        let model = TransactionModel(
            timestamp: input.timestamp,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            recurrenceRuleId: input.recurrenceRuleId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        }
        modelContext.insert(model)
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func addBatch(_ inputs: [TransactionInput]) async throws {
        // Insert all models first, then save once to minimize round-trips
        for input in inputs {
            let model = TransactionModel(
                timestamp: input.timestamp,
                amount: input.amount,
                note: input.note,
                category: input.category,
                currencyCode: input.currencyCode,
                goalId: input.goalId,
                recurrenceRuleId: input.recurrenceRuleId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func delete(id: PersistentIdentifier) async throws {
        guard let model = modelContext.model(for: id) as? TransactionModel else { return }
        modelContext.delete(model)
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func deleteAllTransactions() async throws {
        let all = try modelContext.fetch(FetchDescriptor<TransactionModel>())
        for model in all {
            modelContext.delete(model)
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func update(id: PersistentIdentifier, with input: TransactionInput) async throws {
        guard let model = modelContext.model(for: id) as? TransactionModel else { return }
        model.timestamp = input.timestamp
        model.amount = input.amount
        model.note = input.note
        model.category = input.category
        model.currencyCode = input.currencyCode
        model.goalId = input.goalId
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        } else {
            model.categoryModel = nil
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    // MARK: Recurrence rules

    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws {
        let rule = RecurrenceRule(
            id: input.id,
            frequency: input.frequency,
            interval: input.interval,
            startDate: input.startDate,
            endDate: input.endDate,
            lastMaterializedDate: input.lastMaterializedDate,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            rule.categoryModel = cat
        }
        modelContext.insert(rule)
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot] {
        let today = Calendar.current.startOfDay(for: .now)
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        return all.filter { $0.isActive(asOf: today) }.map(RecurrenceRuleSnapshot.init)
    }

    func fetchAllRecurrenceRules() async throws -> [RecurrenceRuleSnapshot] {
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        return all.map(RecurrenceRuleSnapshot.init)
    }

    func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot? {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return try modelContext.fetch(desc).first.map(RecurrenceRuleSnapshot.init)
    }

    func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.amount = input.amount
        rule.note = input.note
        rule.category = input.category
        rule.currencyCode = input.currencyCode
        rule.goalId = input.goalId
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            rule.categoryModel = cat
        } else {
            rule.categoryModel = nil
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func closeRecurrenceRule(id: UUID, endDate: Date) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.endDate = endDate
        try modelContext.save()
    }

    /// Deletes already-materialized rows for this rule at/after `cutoffDate` (not "future"
    /// rows in the un-materialized sense — every row in the table is materialized). Used to
    /// wipe out rows created under an old template so the next materialize pass regenerates
    /// them under the new one; see the re-entrancy note on RecurrenceMaterializationService.
    func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws {
        let rows = try modelContext.fetch(FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.recurrenceRuleId == recurrenceRuleId && $0.timestamp >= cutoffDate }
        ))
        rows.forEach { modelContext.delete($0) }

        var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == recurrenceRuleId })
        ruleDesc.fetchLimit = 1
        if let rule = try modelContext.fetch(ruleDesc).first {
            // A conservative lower bound (not the exact prior occurrence) is enough: the
            // calculator only needs `since < nextDueOccurrence` to regenerate it correctly.
            rule.lastMaterializedDate = Calendar.current.date(byAdding: .day, value: -1, to: cutoffDate)
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws {
        guard !inputs.isEmpty else { return }
        for input in inputs {
            let model = TransactionModel(
                timestamp: input.timestamp,
                amount: input.amount,
                note: input.note,
                category: input.category,
                currencyCode: input.currencyCode,
                goalId: input.goalId,
                recurrenceRuleId: ruleId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == ruleId })
        ruleDesc.fetchLimit = 1
        if let rule = try modelContext.fetch(ruleDesc).first {
            rule.lastMaterializedDate = newCursor
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    func deleteAllRecurrenceRules() async throws {
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        for model in all {
            modelContext.delete(model)
        }
        try modelContext.save()
        await refreshSafeToSpendWidget()
    }

    // MARK: Categories

    func fetchCategories() async throws -> [CategorySnapshot] {
        let desc = FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(desc).map(CategorySnapshot.init)
    }

    func addCategory(_ input: CategoryInput) async throws {
        let model = CategoryModel(
            name: input.name,
            systemImage: input.systemImage,
            type: TransactionType(rawValue: input.type) ?? .expense,
            colorToken: input.colorToken,
            monthlyBudget: input.monthlyBudget,
            currencyCode: input.currencyCode
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    func deleteCategory(id: PersistentIdentifier) async throws {
        guard let model = modelContext.model(for: id) as? CategoryModel else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: Goals

    func fetchGoals() async throws -> [GoalSnapshot] {
        let desc = FetchDescriptor<GoalModel>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(desc).map(GoalSnapshot.init)
    }

    func addGoal(_ input: GoalInput) async throws {
        let model = GoalModel(
            name: input.name,
            targetAmount: input.targetAmount,
            deadline: input.deadline,
            colorToken: input.colorToken,
            iconName: input.iconName
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    func updateGoal(id: UUID, with input: GoalInput) async throws {
        var desc = FetchDescriptor<GoalModel>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let model = try modelContext.fetch(desc).first else { return }
        model.name = input.name
        model.targetAmount = input.targetAmount
        model.deadline = input.deadline
        model.colorToken = input.colorToken
        model.iconName = input.iconName
        try modelContext.save()
    }

    func deleteGoal(id: UUID) async throws {
        var desc = FetchDescriptor<GoalModel>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let model = try modelContext.fetch(desc).first else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: Health snapshots

    func saveSnapshot(_ data: HealthScoreSnapshotData) async throws {
        let model = HealthScoreSnapshot(
            timestamp: data.timestamp,
            score: data.score,
            savingsScore: data.savingsScore,
            stabilityScore: data.stabilityScore,
            adherenceScore: data.adherenceScore,
            subscriptionScore: data.subscriptionScore
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    func fetchSnapshots(limit: Int) async throws -> [HealthScoreSnapshotData] {
        var desc = FetchDescriptor<HealthScoreSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return try modelContext.fetch(desc).map(HealthScoreSnapshotData.init)
    }

    // MARK: Forecast cache

    func fetchForecastCache() async throws -> DailyForecastCacheData? {
        try modelContext.fetch(FetchDescriptor<DailyForecastCache>()).first.map(DailyForecastCacheData.init)
    }

    func saveForecastCache(_ data: DailyForecastCacheData) async throws {
        let existing = try modelContext.fetch(FetchDescriptor<DailyForecastCache>())
        existing.forEach { modelContext.delete($0) }
        let model = DailyForecastCache(
            monthKey: data.monthKey,
            computedUpToDay: data.computedUpToDay,
            days: data.days,
            amounts: data.amounts
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    // MARK: Safe-to-spend widget refresh

    /// Single place that recomputes and republishes the safe-to-spend snapshot. Called from
    /// every mutation method that can change future spending (see call sites below) — NOT from
    /// saveForecastCache, whose only caller (InsightsViewModel.computeForecast) fires on Insights
    /// recompute, not on a logged transaction, which would leave the widget stale right when
    /// freshness matters most.
    private func refreshSafeToSpendWidget() async {
        guard let transactions = try? await fetchAll(),
              let rules = try? await fetchActiveRecurrenceRules() else { return }
        let payCycleStartDay = await AppSettings.storedStartDay
        let snapshot = SafeToSpendSnapshotBuilder.build(
            transactions: transactions,
            activeRules: rules,
            payCycleStartDay: payCycleStartDay,
            currencyService: CurrencyService()
        )
        try? snapshot.write()
        WidgetCenter.shared.reloadTimelines(ofKind: SafeToSpendWidgetKind.name)
    }
}

extension TransactionActor {
    // #Preview macro expansion can't see the @ModelActor-generated init; this hand-written factory is visible there
    static func make(_ container: ModelContainer) -> TransactionActor {
        TransactionActor(modelContainer: container)
    }
}
