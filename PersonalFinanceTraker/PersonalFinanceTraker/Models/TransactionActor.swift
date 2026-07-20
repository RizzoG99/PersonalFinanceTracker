//  TransactionActor.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

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
            goalId: input.goalId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        }
        modelContext.insert(model)
        try modelContext.save()
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
                goalId: input.goalId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func delete(id: PersistentIdentifier) async throws {
        guard let model = modelContext.model(for: id) as? TransactionModel else { return }
        modelContext.delete(model)
        try modelContext.save()
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
}

extension TransactionActor {
    // #Preview macro expansion can't see the @ModelActor-generated init; this hand-written factory is visible there
    static func make(_ container: ModelContainer) -> TransactionActor {
        TransactionActor(modelContainer: container)
    }
}
