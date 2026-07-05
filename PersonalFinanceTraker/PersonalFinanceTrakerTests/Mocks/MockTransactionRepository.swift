//  MockTransactionRepository.swift
//  PersonalFinanceTrakerTests

import Foundation
import SwiftData
@testable import PersonalFinanceTraker

final class MockTransactionRepository: ITransactionRepository {

    // MARK: Stub data
    var stubbedTransactions: [TransactionSnapshot] = []
    var stubbedCategories: [CategorySnapshot] = []
    var stubbedGoals: [GoalSnapshot] = []
    var stubbedSnapshots: [HealthScoreSnapshotData] = []
    var stubbedForecastCache: DailyForecastCacheData? = nil

    // MARK: Spies
    var fetchAllCalled = false
    var addCalledCount = 0
    var deleteCalledCount = 0
    var updateCalledCount = 0
    var saveSnapshotCalledCount = 0

    // MARK: Error injection
    var shouldThrow = false

    // MARK: Transactions
    func fetchAll() async throws -> [TransactionSnapshot] {
        fetchAllCalled = true
        if shouldThrow { throw MockError.forced }
        return stubbedTransactions
    }

    func add(_ input: TransactionInput) async throws {
        addCalledCount += 1
        if shouldThrow { throw MockError.forced }
    }

    func delete(id: PersistentIdentifier) async throws {
        deleteCalledCount += 1
        if shouldThrow { throw MockError.forced }
        stubbedTransactions.removeAll { $0.id == id }
    }

    func update(id: PersistentIdentifier, with input: TransactionInput) async throws {
        updateCalledCount += 1
        if shouldThrow { throw MockError.forced }
    }

    // MARK: Categories
    func fetchCategories() async throws -> [CategorySnapshot] {
        if shouldThrow { throw MockError.forced }
        return stubbedCategories
    }

    func addCategory(_ input: CategoryInput) async throws {
        if shouldThrow { throw MockError.forced }
    }

    func deleteCategory(id: PersistentIdentifier) async throws {
        if shouldThrow { throw MockError.forced }
    }

    // MARK: Goals
    func fetchGoals() async throws -> [GoalSnapshot] {
        if shouldThrow { throw MockError.forced }
        return stubbedGoals
    }

    func addGoal(_ input: GoalInput) async throws {
        if shouldThrow { throw MockError.forced }
    }

    func updateGoal(id: UUID, with input: GoalInput) async throws {
        if shouldThrow { throw MockError.forced }
    }

    func deleteGoal(id: UUID) async throws {
        if shouldThrow { throw MockError.forced }
    }

    // MARK: Health snapshots
    func saveSnapshot(_ data: HealthScoreSnapshotData) async throws {
        saveSnapshotCalledCount += 1
        if shouldThrow { throw MockError.forced }
        stubbedSnapshots.insert(data, at: 0)
    }

    func fetchSnapshots(limit: Int) async throws -> [HealthScoreSnapshotData] {
        if shouldThrow { throw MockError.forced }
        return Array(stubbedSnapshots.prefix(limit))
    }

    // MARK: Forecast cache
    func fetchForecastCache() async throws -> DailyForecastCacheData? {
        if shouldThrow { throw MockError.forced }
        return stubbedForecastCache
    }

    func saveForecastCache(_ data: DailyForecastCacheData) async throws {
        if shouldThrow { throw MockError.forced }
        stubbedForecastCache = data
    }

    enum MockError: Error { case forced }
}
