//  Snapshots.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData
import SwiftUI

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
    let categorySystemImage: String?
    let categoryColorToken: String?

    init(_ model: TransactionModel) {
        self.id = model.persistentModelID
        self.timestamp = model.timestamp
        self.amount = model.amount
        self.note = model.note
        self.category = model.category
        self.currencyCode = model.currencyCode
        self.goalId = model.goalId
        self.categoryId = model.categoryModel?.persistentModelID
        self.categorySystemImage = model.categoryModel?.systemImage
        self.categoryColorToken = model.categoryModel?.colorToken
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

    var categoryColor: Color {
        Color(colorToken)
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

    var goalColor: Color {
        Color(colorToken)
    }
}

struct HealthScoreSnapshotData: Sendable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let score: Int
    let savingsScore: Int
    let stabilityScore: Int
    let adherenceScore: Int
    let subscriptionScore: Int

    init(timestamp: Date, score: Int, savingsScore: Int, stabilityScore: Int, adherenceScore: Int, subscriptionScore: Int) {
        self.timestamp = timestamp
        self.score = score
        self.savingsScore = savingsScore
        self.stabilityScore = stabilityScore
        self.adherenceScore = adherenceScore
        self.subscriptionScore = subscriptionScore
    }

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

    init(monthKey: String, computedUpToDay: Int, days: [Int], amounts: [Double]) {
        self.monthKey = monthKey
        self.computedUpToDay = computedUpToDay
        self.days = days
        self.amounts = amounts
    }

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

    init(timestamp: Date, amount: Decimal, note: String, category: String, currencyCode: String, goalId: UUID? = nil, categoryPersistentId: PersistentIdentifier? = nil) {
        self.timestamp = timestamp
        self.amount = amount
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.categoryPersistentId = categoryPersistentId
    }
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
