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
    var sharedModelContainer: ModelContainer = AppContainer.shared
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            AuthenticationWrapper(modelContainer: sharedModelContainer)
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
}
