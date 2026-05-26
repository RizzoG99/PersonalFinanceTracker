//
//  PersonalFinanceTrakerApp.swift
//  PersonalFinanceTracker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct PersonalFinanceTrakerApp: App {

    // Dark base color (#030712) set as the window background so the
    // system launch-screen → SwiftUI transition never flashes white.
    init() {
        UIWindow.appearance().backgroundColor = UIColor(
            red: 0.012, green: 0.027, blue: 0.071, alpha: 1
        )
        seedMemberSinceDateIfNeeded()
    }

    // MARK: - Properties

    /// Shared model container for SwiftData persistence
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TransactionModel.self,
            CategoryModel.self,
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
            AuthenticationWrapper(context: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Private Extensions

private extension PersonalFinanceTrakerApp {

    func seedMemberSinceDateIfNeeded() {
        let key = "member_since_timestamp"
        guard UserDefaults.standard.double(forKey: key) == 0 else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key)
    }

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
