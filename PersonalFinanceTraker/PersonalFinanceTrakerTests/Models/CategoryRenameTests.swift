//
//  CategoryRenameTests.swift
//  PersonalFinanceTrakerTests
//
//  #239: renaming a category must carry its transactions and rules along, or list, budgets and
//  charts split it in two (the same failure as #232).
//

import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceTraker

struct CategoryRenameTests {

    private func makeContainer() -> ModelContainer {
        let schema = Schema([TransactionModel.self, CategoryModel.self, GoalModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @Test func renameRewritesItsTransactionsAndRulesOnly() async throws {
        let container = makeContainer()
        let context = ModelContext(container)
        let food = CategoryModel(name: "Food", systemImage: "fork.knife", type: .expense)
        let other = CategoryModel(name: "Fuel", systemImage: "fuelpump", type: .expense)
        context.insert(food)
        context.insert(other)
        for i in 0..<5000 {
            context.insert(TransactionModel(timestamp: Date(), amount: -1, note: "Lunch \(i)", category: "Food", categoryModel: food))
        }
        context.insert(TransactionModel(timestamp: Date(), amount: -40, note: "Fill-up", category: "Fuel", categoryModel: other))
        context.insert(RecurrenceRule(
            frequency: .monthly, interval: 1, startDate: Date(), amount: -30, note: "Meal box",
            category: "Food", currencyCode: "EUR", categoryModel: food
        ))
        try context.save()

        let actor = TransactionActor(modelContainer: container)
        let start = ContinuousClock.now
        let rewritten = try await actor.renameCategory(id: food.persistentModelID, to: "Pasti")
        let elapsed = ContinuousClock.now - start

        #expect(rewritten == 5001)
        // Generous ceiling: catches a per-row save or an O(n²) walk, not CI jitter.
        #expect(elapsed < .seconds(5))
        let all = try await actor.fetchAll()
        #expect(all.filter { $0.category == "Pasti" }.count == 5000)
        #expect(all.first { $0.note == "Fill-up" }?.category == "Fuel")
        #expect(try await actor.fetchCategories().map(\.name).sorted() == ["Fuel", "Pasti"])
        #expect(try await actor.fetchActiveRecurrenceRules().first?.category == "Pasti")
    }

    @Test func renamingAnEmptyCategoryStillSavesTheName() async throws {
        let container = makeContainer()
        let context = ModelContext(container)
        let cat = CategoryModel(name: "Gifts", systemImage: "gift", type: .expense)
        context.insert(cat)
        try context.save()

        let actor = TransactionActor(modelContainer: container)
        #expect(try await actor.renameCategory(id: cat.persistentModelID, to: "Regali") == 0)
        #expect(try await actor.fetchCategories().map(\.name) == ["Regali"])
    }
}
