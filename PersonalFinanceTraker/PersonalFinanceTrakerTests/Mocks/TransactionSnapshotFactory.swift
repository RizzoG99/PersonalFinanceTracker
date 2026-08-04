//
//  TransactionSnapshotFactory.swift
//  PersonalFinanceTrakerTests
//
//  Test factories for Sendable snapshot value types. Snapshots can only be
//  built from SwiftData models, so each helper inserts a model into a shared
//  in-memory container and snapshots it.
//

import Foundation
import SwiftData
@testable import PersonalFinanceTraker

private enum SnapshotTestSupport {
    static let container: ModelContainer = {
        let schema = Schema([TransactionModel.self, CategoryModel.self, GoalModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}

extension TransactionSnapshot {
    static func test(
        timestamp: Date = .now,
        amount: Decimal,
        note: String = "",
        category: String,
        currencyCode: String = "EUR",
        goalId: UUID? = nil,
        recurrenceRuleId: UUID? = nil
    ) -> TransactionSnapshot {
        let context = ModelContext(SnapshotTestSupport.container)
        let model = TransactionModel(
            timestamp: timestamp,
            amount: amount,
            note: note,
            category: category,
            currencyCode: currencyCode,
            goalId: goalId,
            recurrenceRuleId: recurrenceRuleId
        )
        context.insert(model)
        return TransactionSnapshot(model)
    }
}

extension CategorySnapshot {
    static func test(
        name: String,
        systemImage: String = "tag",
        type: TransactionType = .expense,
        monthlyBudget: Decimal? = nil,
        currencyCode: String = "EUR"
    ) -> CategorySnapshot {
        let context = ModelContext(SnapshotTestSupport.container)
        let model = CategoryModel(
            name: name,
            systemImage: systemImage,
            type: type,
            monthlyBudget: monthlyBudget,
            currencyCode: currencyCode
        )
        context.insert(model)
        return CategorySnapshot(model)
    }
}

extension GoalSnapshot {
    static func test(
        name: String,
        targetAmount: Decimal,
        deadline: Date? = nil
    ) -> GoalSnapshot {
        let context = ModelContext(SnapshotTestSupport.container)
        let model = GoalModel(name: name, targetAmount: targetAmount, deadline: deadline)
        context.insert(model)
        return GoalSnapshot(model)
    }
}

extension RecurrenceRuleSnapshot {
    static func test(
        id: UUID = UUID(),
        frequency: RecurrenceFrequency = .monthly,
        interval: Int = 1,
        startDate: Date,
        endDate: Date? = nil,
        lastMaterializedDate: Date? = nil,
        amount: Decimal,
        note: String = "",
        category: String,
        currencyCode: String = "EUR",
        goalId: UUID? = nil
    ) -> RecurrenceRuleSnapshot {
        let context = ModelContext(SnapshotTestSupport.container)
        let model = RecurrenceRule(
            id: id, frequency: frequency, interval: interval, startDate: startDate,
            endDate: endDate, lastMaterializedDate: lastMaterializedDate,
            amount: amount, note: note, category: category, currencyCode: currencyCode, goalId: goalId
        )
        context.insert(model)
        return RecurrenceRuleSnapshot(model)
    }
}
