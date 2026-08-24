import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct DataWipeServiceTests {

    private func makeSeededContext() -> ModelContext {
        let schema = Schema([
            TransactionModel.self,
            RecurrenceRule.self,
            CategoryModel.self,
            CreditCardModel.self,
            GoalModel.self,
            HealthScoreSnapshot.self,
            DailyForecastCache.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        // Categories + transactions via the app's existing sample data
        SampleData.populateModelContext(context)

        // One instance of each of the remaining models
        context.insert(CreditCardModel(name: "Test Card", lastFour: "1234", balance: 100, limit: 1000))
        context.insert(GoalModel(name: "Test Goal", targetAmount: 500))
        context.insert(HealthScoreSnapshot(
            timestamp: .now, score: 80, savingsScore: 80,
            stabilityScore: 80, adherenceScore: 80, subscriptionScore: 80
        ))
        context.insert(DailyForecastCache(monthKey: "2026-07", computedUpToDay: 1, days: [1], amounts: [10]))
        context.insert(RecurrenceRule(
            frequency: .monthly, interval: 1, startDate: .now,
            amount: -9.99, note: "iCloud", category: "Abbonamenti", currencyCode: "EUR"
        ))
        try! context.save()

        return context
    }

    @Test("wipeAllData removes every model type")
    func wipesAllModels() throws {
        let context = makeSeededContext()

        // Sanity check: seeded data exists before wiping
        #expect(try context.fetchCount(FetchDescriptor<TransactionModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<CategoryModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<CreditCardModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<GoalModel>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthScoreSnapshot>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<DailyForecastCache>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<RecurrenceRule>()) > 0)

        try DataWipeService.wipeAllData(context: context)

        #expect(try context.fetchCount(FetchDescriptor<TransactionModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CategoryModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CreditCardModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GoalModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthScoreSnapshot>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<DailyForecastCache>()) == 0)
        // Survivors here re-materialize transactions at the next launch and suppress every
        // import recurrence suggestion, because each candidate still matches a live rule.
        #expect(try context.fetchCount(FetchDescriptor<RecurrenceRule>()) == 0)
    }

    @Test("wipeAllData is idempotent on an already-empty context")
    func wipingEmptyContextDoesNotThrow() throws {
        let context = makeSeededContext()
        try DataWipeService.wipeAllData(context: context)

        // Calling again on an already-empty store must not throw
        try DataWipeService.wipeAllData(context: context)

        #expect(try context.fetchCount(FetchDescriptor<TransactionModel>()) == 0)
    }
}
