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

    /// Drives the window appearance applied below. Key must match
    /// `ProfileAppearanceSection`.
    @AppStorage("app_theme_mode") private var themeMode: ThemeMode = .auto

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            AuthenticationWrapper(modelContainer: sharedModelContainer)
                // Single place the app's appearance is declared. Eight views used to
                // pin `.preferredColorScheme(.dark)` on their own bodies, which meant a
                // descendant silently overrode any app-level choice.
                //
                // Applied to the window rather than via `.preferredColorScheme`: that
                // modifier only reaches its own presentation container, so a sheet that
                // was already on screen kept its original appearance — including the
                // Settings sheet that hosts the picker. Setting the window's trait
                // propagates to every view controller it owns, presented sheets included.
                .onChange(of: themeMode, initial: true) { _, mode in
                    applyAppearance(mode)
                }
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

    /// Pushes the chosen appearance onto every window in the scene. `.unspecified`
    /// hands control back to the system, which is what Auto means.
    @MainActor
    func applyAppearance(_ mode: ThemeMode) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = mode.uiStyle
            }
        }
    }

    func seedMemberSinceDateIfNeeded() {
        let key = "member_since_timestamp"
        guard UserDefaults.standard.double(forKey: key) == 0 else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key)
    }
}
