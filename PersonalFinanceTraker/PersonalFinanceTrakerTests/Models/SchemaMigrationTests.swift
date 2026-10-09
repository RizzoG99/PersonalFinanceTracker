//
//  SchemaMigrationTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

/// Copy of the model #191 removed from the app. SwiftData maps a model to its stored entity
/// by class name, so this recreates a store exactly as released builds left it.
@Model
final class DailyForecastCache {
    var monthKey: String
    var computedUpToDay: Int
    var days: [Int]
    var amounts: [Double]

    init(monthKey: String, computedUpToDay: Int, days: [Int], amounts: [Double]) {
        self.monthKey = monthKey
        self.computedUpToDay = computedUpToDay
        self.days = days
        self.amounts = amounts
    }
}

/// The app has no migration plan (#218): it relies on SwiftData's automatic lightweight
/// migration. This proves an existing on-disk store still opens, data intact, after a
/// model is dropped from the schema — the alternative is "reinstall", i.e. data loss.
struct SchemaMigrationTests {
    private static let current: [any PersistentModel.Type] = [
        TransactionModel.self, CategoryModel.self, CreditCardModel.self, GoalModel.self,
        TravelModel.self, HealthScoreSnapshot.self, RecurrenceRule.self, MerchantCategoryMapping.self,
    ]

    @Test("a store written with DailyForecastCache opens without it, data intact")
    func droppingForecastCacheKeepsData() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "store.sqlite")

        do {
            let schema = Schema(Self.current + [DailyForecastCache.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            context.insert(TransactionModel(timestamp: .now, amount: -42, note: "kept", category: "Groceries"))
            context.insert(DailyForecastCache(monthKey: "2026-09", computedUpToDay: 3, days: [1, 2, 3], amounts: [1, 2, 3]))
            try context.save()
        }

        let schema = Schema(Self.current)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let transactions = try ModelContext(container).fetch(FetchDescriptor<TransactionModel>())
        #expect(transactions.map(\.note) == ["kept"])
        #expect(transactions.first?.amount == -42)
    }
}
