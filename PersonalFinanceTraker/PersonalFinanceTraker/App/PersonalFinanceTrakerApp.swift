//
//  PersonalFinanceTrakerApp.swift
//  PersonalFinanceTracker
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import SwiftUI
import SwiftData
import TipKit
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
        configureTips()
        seedSampleDataIfRequested()
    }

    // MARK: - Properties

    /// Shared model container for SwiftData persistence
    var sharedModelContainer: ModelContainer = AppContainer.shared

    /// Alert state for container creation errors
    @State private var containerErrorMessage: String?

    /// Drives the window appearance applied below. Key must match
    /// `ProfileAppearanceSection`.
    @AppStorage("app_theme_mode") private var themeMode: ThemeMode = .auto
    @AppStorage("pending_widget_destination") private var pendingWidgetDestination = ""

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            AuthenticationWrapper(modelContainer: sharedModelContainer)
                // Single place the app's appearance is declared. Eight views used to
                // pin `.preferredColorScheme(.dark)` on their own bodies, which meant a
                // descendant silently overrode any app-level choice.
                //
                // Both mechanisms, because neither covers the whole app alone:
                // `.preferredColorScheme` restyles the SwiftUI hierarchy including
                // system chrome (the floating tab bar, glass toolbar buttons) but
                // does not reach an already-presented sheet; the window trait reaches
                // presented containers but leaves that chrome untouched. Same value
                // from the same source, so they cannot disagree.
                .preferredColorScheme(themeMode.colorScheme)
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
                .onOpenURL { url in
                    guard url.scheme == "personalfinancetraker" else { return }
                    switch url.host {
                    case "add-transaction":
                        PendingTransactionIntent.shared.shouldPresentAdd = true
                    case "review-transaction":
                        guard let request = PendingHabitTemplateRequest(widgetURL: url) else { return }
                        PendingHabitTemplateStore.save(request)
                        PendingTransactionIntent.shared.shouldReviewHabitTemplate = true
                    case "scan-receipt":
                        PendingTransactionIntent.shared.shouldScanReceipt = true
                    case "insights":
                        pendingWidgetDestination = "insights"
                    default:
                        break
                    }
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
            // A presented (not embedded) controller reliably re-renders when its
            // override is set to a *concrete* .light/.dark — that's the path Light
            // and Dark already use. Setting `.unspecified` on a presented controller
            // removes the override but doesn't reliably force it to re-resolve from
            // its ambient trait, so Auto needs a resolved concrete value here too.
            // The window itself keeps `.unspecified` for Auto — the root hierarchy
            // (not a presented controller) does track system changes live via that.
            let resolvedForPresented: UIUserInterfaceStyle =
                mode == .auto ? windowScene.traitCollection.userInterfaceStyle : mode.uiStyle
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = mode.uiStyle
                var presented = window.rootViewController?.presentedViewController
                while let controller = presented {
                    controller.overrideUserInterfaceStyle = resolvedForPresented
                    presented = controller.presentedViewController
                }
            }
        }
    }

    func seedMemberSinceDateIfNeeded() {
        let key = "member_since_timestamp"
        guard UserDefaults.standard.double(forKey: key) == 0 else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key)
    }

    /// `-seedSampleData` replaces the store with `SampleData`'s fixed set so the
    /// screenshot pass (`scripts/screenshots`) always shoots the same populated app.
    /// `AppContainer` seeds default categories on every launch, and
    /// `populateModelContext` no-ops when any category exists, so the wipe comes first.
    @MainActor
    func seedSampleDataIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData") else { return }
        let context = AppContainer.shared.mainContext
        try? context.delete(model: TransactionModel.self)
        try? context.delete(model: CategoryModel.self)
        try? context.save()
        SampleData.populateModelContext(context)
        // SampleData sets no budgets, which leaves the Budgets screen reading
        // "No limit" for every row — true, but it shows nothing about the feature.
        let budgets: [String: Decimal] = [
            "Groceries": 400, "Restaurants": 200, "Coffee & Drinks": 60,
            "Gas": 150, "Streaming Services": 40, "Clothing": 120,
        ]
        let categories = (try? context.fetch(FetchDescriptor<CategoryModel>())) ?? []
        for category in categories {
            category.monthlyBudget = budgets[category.name]
        }
        try? context.save()
        #endif
    }

    /// `-resetTips` lets a Debug build re-see already-shown tips without an
    /// uninstall — the shared simulator is also used for manual testing that
    /// shouldn't get wiped by a reinstall (see feedback_shared_simulator_collision).
    func configureTips() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetTips") {
            try? Tips.resetDatastore()
        }
        // Tip popovers land on top of whatever is being captured, so the screenshot
        // pass turns them off wholesale rather than dismissing them one by one.
        if ProcessInfo.processInfo.arguments.contains("-hideTips") {
            Tips.hideAllTipsForTesting()
        }
        #endif
        try? Tips.configure()
    }
}
