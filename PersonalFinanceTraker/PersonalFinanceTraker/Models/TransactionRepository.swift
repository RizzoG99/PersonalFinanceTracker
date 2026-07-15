//  TransactionRepository.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

protocol ITransactionRepository {
    // Transactions
    func fetchAll() async throws -> [TransactionSnapshot]
    func add(_ input: TransactionInput) async throws
    func addBatch(_ inputs: [TransactionInput]) async throws
    func delete(id: PersistentIdentifier) async throws
    func update(id: PersistentIdentifier, with input: TransactionInput) async throws

    // Categories
    func fetchCategories() async throws -> [CategorySnapshot]
    func addCategory(_ input: CategoryInput) async throws
    func deleteCategory(id: PersistentIdentifier) async throws

    // Goals
    func fetchGoals() async throws -> [GoalSnapshot]
    func addGoal(_ input: GoalInput) async throws
    func updateGoal(id: UUID, with input: GoalInput) async throws
    func deleteGoal(id: UUID) async throws

    // Health snapshots
    func saveSnapshot(_ data: HealthScoreSnapshotData) async throws
    func fetchSnapshots(limit: Int) async throws -> [HealthScoreSnapshotData]

    // Forecast cache
    func fetchForecastCache() async throws -> DailyForecastCacheData?
    func saveForecastCache(_ data: DailyForecastCacheData) async throws
}
