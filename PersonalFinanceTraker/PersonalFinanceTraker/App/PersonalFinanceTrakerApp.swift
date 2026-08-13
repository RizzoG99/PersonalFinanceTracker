//
//  PersonalFinanceTrakerApp.swift
//  PersonalFinanceTracker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct PersonalFinanceTrakerApp: App {

    // Base color set as the window background so the system launch-screen →
    // SwiftUI transition never flashes. Reads the LaunchBackground colorset so the
    // window, the launch screen and AppBackground's base can never drift apart.
    init() {
        UIWindow.appearance().backgroundColor = UIColor(named: "LaunchBackground")
        seedMemberSinceDateIfNeeded()
        UNUserNotificationCenter.current().delegate = NotificationTapHandler.shared
    }

    // MARK: - Properties

    /// Shared model container for SwiftData persistence
    var sharedModelContainer: ModelContainer = AppContainer.shared

    /// Alert state for container creation errors
    @State private var containerErrorMessage: String?

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            AuthenticationWrapper(modelContainer: sharedModelContainer)
                // Single place the app's appearance is declared. Previously eight views
                // each pinned `.preferredColorScheme(.dark)` on their own body, which
                // meant a descendant silently overrode any app-level choice. Becomes
                // `themeMode.colorScheme` when the Appearance picker lands.
                .preferredColorScheme(.dark)
                .alert("Data Access Error", isPresented: .constant(containerErrorMessage != nil)) {
                    Button("OK") {
                        containerErrorMessage = nil
                    }
                } message: {
                    if let message = containerErrorMessage {
                        Text(message)
                    }
                }
                .onAppear {
                    containerErrorMessage = AppContainer.containerErrorMessage
                }
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
