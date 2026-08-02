//
//  AppContainer.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// Single shared container — used by the app scene and by App Intents, which
/// run in-process but can't reach the App struct's instance property.
enum AppContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            TransactionModel.self,
            CategoryModel.self,
            CreditCardModel.self,
            GoalModel.self,
            HealthScoreSnapshot.self,
            DailyForecastCache.self,
            RecurrenceRule.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            // Default categories are real app data (not sample data) — every user,
            // debug or release, needs them to add a transaction. Always reseed when
            // empty, including right after Delete All Data wipes CategoryModel.
            MainActor.assumeIsolated { seedDefaultCategoriesIfNeeded(in: container) }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @MainActor
    private static func seedDefaultCategoriesIfNeeded(in container: ModelContainer) {
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<CategoryModel>())) ?? 0
        guard count == 0 else { return }
        for category in SampleData.createSampleCategories() {
            context.insert(category)
        }
        try? context.save()
    }
}
