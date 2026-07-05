//  Snapshots.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

// MARK: - Read snapshots (Sendable value types for crossing actor boundaries)

struct TransactionSnapshot: Identifiable, Sendable, Hashable {
    let id: PersistentIdentifier
    let timestamp: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let categoryId: PersistentIdentifier?

    init(_ model: TransactionModel) {
        self.id = model.persistentModelID
        self.timestamp = model.timestamp
        self.amount = model.amount
        self.note = model.note
        self.category = model.category
        self.currencyCode = model.currencyCode
        self.goalId = model.goalId
        self.categoryId = model.categoryModel?.persistentModelID
    }
}

struct CategorySnapshot: Identifiable, Sendable, Hashable {
    let id: UUID
    let persistentId: PersistentIdentifier
    let name: String
    let systemImage: String
    let type: String
    let colorToken: String
    let monthlyBudget: Decimal?
    let currencyCode: String

    init(_ model: CategoryModel) {
        self.id = model.id
        self.persistentId = model.persistentModelID
        self.name = model.name
        self.systemImage = model.systemImage
        self.type = model.type
        self.colorToken = model.colorToken
        self.monthlyBudget = model.monthlyBudget
        self.currencyCode = model.currencyCode
    }

    var transactionType: TransactionType {
        TransactionType(rawValue: type) ?? .expense
    }
}

struct GoalSnapshot: Identifiable, Sendable, Hashable {
    let id: UUID
    let persistentId: PersistentIdentifier
    let name: String
    let targetAmount: Decimal
    let deadline: Date?
    let colorToken: String
    let iconName: String
    let createdAt: Date

    init(_ model: GoalModel) {
        self.id = model.id
        self.persistentId = model.persistentModelID
        self.name = model.name
        self.targetAmount = model.targetAmount
        self.deadline = model.deadline
        self.colorToken = model.colorToken
        self.iconName = model.iconName
        self.createdAt = model.createdAt
    }
}

struct HealthScoreSnapshotData: Sendable {
    let timestamp: Date
    let score: Int
    let savingsScore: Int
    let stabilityScore: Int
    let adherenceScore: Int
    let subscriptionScore: Int

    init(_ model: HealthScoreSnapshot) {
        self.timestamp = model.timestamp
        self.score = model.score
        self.savingsScore = model.savingsScore
        self.stabilityScore = model.stabilityScore
        self.adherenceScore = model.adherenceScore
        self.subscriptionScore = model.subscriptionScore
    }
}

struct DailyForecastCacheData: Sendable {
    let monthKey: String
    let computedUpToDay: Int
    let days: [Int]
    let amounts: [Double]

    init(_ model: DailyForecastCache) {
        self.monthKey = model.monthKey
        self.computedUpToDay = model.computedUpToDay
        self.days = model.days
        self.amounts = model.amounts
    }
}

// MARK: - Write inputs (Sendable, no model references)

struct TransactionInput: Sendable {
    let timestamp: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let categoryPersistentId: PersistentIdentifier?
}

struct CategoryInput: Sendable {
    let name: String
    let systemImage: String
    let type: String
    let colorToken: String
    let monthlyBudget: Decimal?
    let currencyCode: String
}

struct GoalInput: Sendable {
    var name: String
    var targetAmount: Decimal
    var deadline: Date?
    var colorToken: String
    var iconName: String
}
