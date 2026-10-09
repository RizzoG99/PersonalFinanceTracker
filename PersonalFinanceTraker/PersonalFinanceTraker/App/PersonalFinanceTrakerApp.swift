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
        seedFixedExpenseCardsIfRequested()
        seedMonthCardIfRequested()
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
                    case "insights", "home":
                        pendingWidgetDestination = url.host ?? ""
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

    /// `-seedFixedExpenseCards` replaces transactions, recurring rules and goals with every
    /// fixed-expense card state (#206): two missed payments (an expense and a goal transfer)
    /// and four suggestions, one with a varying amount — more than Plan shows inline, so
    /// "Review N more" appears too. Dates are relative to today, so it works any day.
    @MainActor
    func seedFixedExpenseCardsIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-seedFixedExpenseCards") else { return }
        let context = AppContainer.shared.mainContext
        try? context.delete(model: TransactionModel.self)
        try? context.delete(model: RecurrenceRule.self)
        try? context.delete(model: GoalModel.self)
        UserDefaults.standard.removeObject(forKey: "dismissedRecurrencePatterns")

        let calendar = Calendar.current
        func monthsAgo(_ months: Int, plusDays days: Int) -> Date {
            let date = calendar.date(byAdding: .month, value: -months, to: .now)!
            return calendar.date(byAdding: .day, value: -days, to: date)!
        }

        // Missed: forecast-only rules whose last due date (~10 days ago) has no payment.
        let goal = GoalModel(name: "Emergency fund", targetAmount: 5000)
        context.insert(goal)
        let cursor = monthsAgo(1, plusDays: 10)
        context.insert(RecurrenceRule(
            frequency: .monthly, interval: 1, startDate: cursor, lastMaterializedDate: cursor,
            autoRecord: false, amount: -35, note: "Palestra", category: "Gym & Fitness", currencyCode: "EUR"
        ))
        context.insert(RecurrenceRule(
            frequency: .monthly, interval: 1, startDate: cursor, lastMaterializedDate: cursor,
            autoRecord: false, amount: -200, note: "", category: "→ Emergency fund", currencyCode: "EUR", goalId: goal.id
        ))

        // Suggestions: monthly series whose next payment is still a few days away.
        let series: [(note: String, category: String, amounts: [Decimal])] = [
            ("Netflix", "Streaming Services", [-13.99, -13.99]),
            ("Affitto", "Rent/Mortgage", [-650, -650]),
            ("Fastweb", "Internet", [-29.95, -29.95]),
            ("Enel", "Utilities", [-80, -86, -83]),
        ]
        for (note, category, amounts) in series {
            for (index, amount) in amounts.enumerated() {
                context.insert(TransactionModel(
                    timestamp: monthsAgo(amounts.count - index, plusDays: -5),
                    amount: amount, note: note, category: category
                ))
            }
        }
        try? context.save()
        #endif
    }

    /// `-seedMonthCard <state>` replaces transactions, rules and goals with three ordinary
    /// earlier pay cycles plus a current one in the requested Home month card state (#191):
    /// `onTrack` (with a goal transfer), `faster`, `building`, `noIncome`, `overspent`, `hidden`.
    /// It also moves the pay-cycle start day so today is 12 days in (3 for `building`).
    @MainActor
    func seedMonthCardIfRequested() {
        #if DEBUG
        guard let state = UserDefaults.standard.string(forKey: "seedMonthCard") else { return }
        let context = AppContainer.shared.mainContext
        try? context.delete(model: TransactionModel.self)
        try? context.delete(model: RecurrenceRule.self)
        try? context.delete(model: GoalModel.self)

        let calendar = Calendar.current
        let elapsed = state == "building" ? 3 : 12
        let anchor = calendar.date(byAdding: .day, value: -elapsed, to: .now)!
        let startDay = min(calendar.component(.day, from: anchor), 28)
        UserDefaults.standard.set(startDay, forKey: "payCycleStartDay")
        let cycleStart = PayCycleService.financialMonthStart(for: .now, startDay: startDay, calendar: calendar)
        let daysIn = calendar.dateComponents([.day], from: cycleStart, to: .now).day ?? elapsed

        func add(_ amount: Decimal, _ category: String, day: Int, cyclesAgo: Int, goalId: UUID? = nil) {
            // The current cycle only gets what has already happened.
            guard cyclesAgo > 0 || day < daysIn else { return }
            let start = calendar.date(byAdding: .month, value: -cyclesAgo, to: cycleStart)!
            let date = calendar.date(byAdding: .hour, value: 10, to: calendar.date(byAdding: .day, value: day, to: start)!)!
            context.insert(TransactionModel(timestamp: date, amount: amount, note: "", category: category, goalId: goalId))
        }
        func usualCycle(_ cyclesAgo: Int, income: Decimal? = 2000) {
            if let income { add(income, "Salary", day: 0, cyclesAgo: cyclesAgo) }
            add(-650, "Rent/Mortgage", day: 1, cyclesAgo: cyclesAgo)
            for day in [2, 6, 10, 14, 18, 22] { add(-60, "Groceries", day: day, cyclesAgo: cyclesAgo) }
            for day in [4, 11, 20] { add(-30, "Restaurants", day: day, cyclesAgo: cyclesAgo) }
            for day in [3, 15] { add(-40, "Gas", day: day, cyclesAgo: cyclesAgo) }
        }

        for cyclesAgo in 1...3 { usualCycle(cyclesAgo) }
        switch state {
        case "onTrack":
            usualCycle(0)
            let goal = GoalModel(name: "Emergency fund", targetAmount: 5000)
            context.insert(goal)
            add(-200, "→ Emergency fund", day: 2, cyclesAgo: 0, goalId: goal.id)
        case "faster", "overspent":
            usualCycle(0, income: state == "faster" ? 2000 : 800)
            for day in [5, 7, 9] { add(-55, "Restaurants", day: day, cyclesAgo: 0) }
            add(-90, "Gas", day: 8, cyclesAgo: 0)
        case "building":
            usualCycle(0)
        case "noIncome":
            usualCycle(0, income: nil)
        default: // "hidden": nothing this cycle
            break
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
            UserDefaults.standard.removeObject(forKey: "add_transaction_opened_once")
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
