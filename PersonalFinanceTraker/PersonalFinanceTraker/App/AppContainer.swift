//
//  AppContainer.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData
import UIKit

/// Single shared container — used by the app scene and by App Intents, which
/// run in-process but can't reach the App struct's instance property.
enum AppContainer {
    /// Error state when ModelContainer creation fails.
    /// Minimal in-app recovery: display a message, offer app restart/reinstall options.
    static var containerCreationError: Error?

    /// Check if a container creation error occurred and return a user-facing message.
    static var containerErrorMessage: String? {
        guard let error = containerCreationError else { return nil }
        return "Unable to access your data. Please restart the app or reinstall if the issue persists."
    }

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
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
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

            // Harden the store file protection so the SQLite database is unreadable
            // while the device is locked. Must be called after container creation.
            if let storeURL = modelConfiguration.url {
                hardenStore(at: storeURL)
            }

            return container
        } catch {
            // Store the error for graceful recovery UI instead of crashing.
            containerCreationError = error
            // Return a dummy in-memory container so the app can boot and show the error.
            let fallbackSchema = Schema([
                TransactionModel.self,
                CategoryModel.self,
                CreditCardModel.self,
                GoalModel.self,
                HealthScoreSnapshot.self,
                DailyForecastCache.self,
                RecurrenceRule.self,
            ])
            let fallbackConfig = ModelConfiguration(
                schema: fallbackSchema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(
                    for: fallbackSchema,
                    configurations: [fallbackConfig]
                )
            } catch {
                // Absolute fallback — something is deeply broken. Let the app crash
                // so it can be debugged, but log the original error.
                fatalError("Could not create ModelContainer (original: \(containerCreationError ?? error))")
            }
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

    /// Harden the SwiftData store's file protection so the SQLite database is
    /// unreadable while the device is locked. Guards with isProtectedDataAvailable
    /// and silently skips if protection is not possible — the next launch will retry.
    /// ponytail: hardening can fail if device is locked; gracefully retry on next launch.
    private static func hardenStore(at url: URL) {
        // Only apply protection when the device is unlocked (isProtectedDataAvailable).
        // Once tightened, the file remains protected; a future (locked) launch sees the
        // complete protection from disk.
        guard UIApplication.shared.isProtectedDataAvailable else {
            return
        }

        let fileManager = FileManager.default
        // SQLite sidecars use -wal and -shm suffixes appended directly to the store path,
        // not additional extensions. Protect main file + both sidecars.
        let files = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]

        for file in files {
            do {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: file.path
                )
            } catch {
                // Silently skip file-not-found errors (e.g., -wal/-shm may not exist yet).
                // Log other errors but never throw — app start must never be blocked.
                if (error as NSError).code != NSFileNoSuchFileError {
                    print("Warning: could not harden store file at \(file.lastPathComponent): \(error)")
                }
            }
        }
    }
}
