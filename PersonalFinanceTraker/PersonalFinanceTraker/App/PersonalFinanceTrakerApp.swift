//
//  PersonalFinanceTrakerApp.swift
//  PersonalFinanceTracker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData

@main
struct PersonalFinanceTrakerApp: App {
    
    // MARK: - Properties
    
    /// Shared model container for SwiftData persistence
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TransactionModel.self,
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
            
            #if DEBUG
            setupSampleDataIfNeeded(in: container)
            #endif
            
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Private Extensions

private extension PersonalFinanceTrakerApp {
    
    /// Sets up sample data in debug builds if no existing data is found
    /// - Parameter container: The model container to populate
    static func setupSampleDataIfNeeded(in container: ModelContainer) {
        let context = container.mainContext
        let fetchDescriptor = FetchDescriptor<TransactionModel>()
        
        do {
            let existingItems = try context.fetch(fetchDescriptor)
            if existingItems.isEmpty {
                SampleData.populateModelContext(context)
                print("Sample data added to the app")
            }
        } catch {
            print("Error checking for existing data: \(error)")
        }
    }
}
