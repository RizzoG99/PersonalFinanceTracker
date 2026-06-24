//
//  MockTransactionRepository.swift
//  PersonalFinanceTrakerTests
//

import Foundation
@testable import PersonalFinanceTraker

final class MockTransactionRepository: ITransactionRepository {
    var transactions: [TransactionModel] = []
    var categories: [CategoryModel] = []
    var goals: [GoalModel] = []
    var snapshots: [HealthScoreSnapshot] = []
    var forecastCache: DailyForecastCache?
    var shouldFail: Bool = false

    // Track calls for verification (Spy pattern)
    var fetchAllCalled = false
    var addCalledCount = 0
    var deleteCalledCount = 0
    var updateCalledCount = 0
    var saveSnapshotCalledCount = 0

    func fetchAll() throws -> [TransactionModel] {
        fetchAllCalled = true
        if shouldFail { throw NSError(domain: "MockError", code: 1, userInfo: nil) }
        return transactions
    }

    func add(_ item: TransactionModel) throws {
        addCalledCount += 1
        if shouldFail { throw NSError(domain: "MockError", code: 2, userInfo: nil) }
        transactions.append(item)
    }

    func delete(_ item: TransactionModel) throws {
        deleteCalledCount += 1
        if let index = transactions.firstIndex(where: { $0.id == item.id }) {
            transactions.remove(at: index)
        }
        if shouldFail { throw NSError(domain: "MockError", code: 3, userInfo: nil) }
    }

    func update() throws {
        updateCalledCount += 1
        if shouldFail { throw NSError(domain: "MockError", code: 4, userInfo: nil) }
    }

    func fetchCategories() throws -> [CategoryModel] { categories }
    func addCategory(_ item: CategoryModel) throws { categories.append(item) }
    func deleteCategory(_ item: CategoryModel) throws { categories.removeAll { $0.id == item.id } }

    func fetchGoals() throws -> [GoalModel] { goals }
    func addGoal(_ item: GoalModel) throws { goals.append(item) }
    func updateGoal() throws {}
    func deleteGoal(_ item: GoalModel) throws { goals.removeAll { $0.id == item.id } }

    func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws {
        saveSnapshotCalledCount += 1
        if shouldFail { throw NSError(domain: "MockError", code: 5, userInfo: nil) }
        snapshots.append(snapshot)
    }

    func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot] {
        if shouldFail { throw NSError(domain: "MockError", code: 6, userInfo: nil) }
        return Array(snapshots.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func fetchForecastCache() throws -> DailyForecastCache? {
        if shouldFail { throw NSError(domain: "MockError", code: 7, userInfo: nil) }
        return forecastCache
    }

    func saveForecastCache(_ cache: DailyForecastCache) throws {
        if shouldFail { throw NSError(domain: "MockError", code: 8, userInfo: nil) }
        forecastCache = cache
    }
}
