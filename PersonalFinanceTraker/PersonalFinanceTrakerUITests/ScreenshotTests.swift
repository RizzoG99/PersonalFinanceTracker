//
//  ScreenshotTests.swift
//  PersonalFinanceTrakerUITests
//
//  Walks the app and writes one PNG per screen, so README/marketing shots can be
//  regenerated instead of re-captured by hand. Driven by `scripts/screenshots`,
//  which sets SCREENSHOT_DIR and flips the simulator appearance between passes.
//
//  ponytail: elements are matched by their English labels rather than added
//  accessibility identifiers — the launch forces en, so the labels are stable and
//  the app needs no screenshot-only markup. Add identifiers if the copy churns.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var outputDirectory: URL?

    /// Shows up in the profile header and the greeting, so it's part of the shot.
    private let screenshotUserName = "Alex"


    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR not set — run via scripts/screenshots")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory
    }

    // MARK: - The walk

    @MainActor
    func testCaptureScreenshots() throws {
        let app = launchApp()

        if UIDevice.current.userInterfaceIdiom == .pad {
            try capturePad(app)
        } else {
            try capturePhone(app)
        }
    }

    @MainActor
    private func capturePhone(_ app: XCUIApplication) throws {
        completeOnboarding(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar never appeared")
        settle()
        try shoot("01-dashboard")

        tapTab(app, "Activity")
        try shoot("02-activity")

        tapTab(app, "Insights")
        try shoot("04-insights")

        tapTab(app, "Home")
        tap(app.buttons["Add transaction"])
        // The amount field takes focus on open, and the keyboard hides most of the
        // form — the accessory's Done dismisses it without leaving the sheet.
        tapIfPresent(app.buttons["Done"], timeout: 5)
        try shoot("05-add-transaction")
        dismissSheet(app)

        openProfile(app)
        try shoot("06-settings")

        scrollTo(app.buttons["Manage Categories"], in: app)
        tap(app.buttons["Manage Categories"])
        try shoot("07-categories")
        goBack(app)

        // Prefix match: the row appends a "N set" count once budgets exist, so its
        // accessibility label is not just the title.
        let budgets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Manage Budgets")).firstMatch
        scrollTo(budgets, in: app)
        tap(budgets)
        try shoot("08-budgets")
        goBack(app)

        // The import mapping screen sits behind the system document picker, which is
        // another process and not worth driving — the Data section shows the same
        // import/export capability. ponytail: swap in the mapping screen if it ever
        // gets a launch-arg entry point.
        scrollTo(app.buttons["Import CSV or Excel"], in: app)
        try shoot("09-import-export")
        dismissSheet(app)

        // Last on purpose: the keyboard covers the tab bar and the search field's
        // dismiss control is an unlabelled glyph, so there is no reliable way back
        // out. Ending here means there is nothing to get back to.
        tapTab(app, "Activity")
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 10) {
            search.tap()
            search.typeText("Coffee")
            try shoot("03-activity-search")
        }
    }

    @MainActor
    private func capturePad(_ app: XCUIApplication) throws {
        completeOnboarding(app)
        settle()
        try shoot("01-dashboard")

        tapSidebar(app, "Activity")
        try shoot("02-ledger")

        tapSidebar(app, "Insights")
        try shoot("03-insights")

        tapSidebar(app, "Health Score")
        try shoot("04-health-score")

        tapSidebar(app, "Settings")
        try shoot("05-settings")
    }

    // MARK: - Helpers

    /// A clean install opens on PIN setup, not the app: PIN → confirm → optional
    /// biometric prompt → name → optional iCloud restore prompt. The script
    /// uninstalls before each pass, so this always runs and always the same way.
    @MainActor
    private func completeOnboarding(_ app: XCUIApplication) {
        guard app.staticTexts["Enter new PIN"].waitForExistence(timeout: 60) else { return }
        enterPIN(app)
        XCTAssertTrue(app.staticTexts["Confirm new PIN"].waitForExistence(timeout: 10), "PIN never advanced to confirm")
        enterPIN(app)

        // Biometric step is skipped entirely when the simulator has no enrolled
        // sensor, so both this and the restore prompt below are best-effort.
        tapIfPresent(app.buttons["Skip"], timeout: 10)

        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 10) {
            nameField.tap()
            nameField.typeText(screenshotUserName)
            tapIfPresent(app.buttons["Continue"], timeout: 5)
        }

        tapIfPresent(app.buttons["Skip"], timeout: 5)

        // The tour is off via UserDefaults, but the What's New sheet is keyed on the
        // *current* app version, which the test can't know — so dismiss it here rather
        // than trying to pre-seed feature_discovery_last_seen_release_version.
        tapIfPresent(app.buttons["Done"], timeout: 10)
    }

    @MainActor
    private func enterPIN(_ app: XCUIApplication) {
        for digit in ["1", "2", "3", "4"] {
            let key = app.buttons[digit]
            XCTAssertTrue(key.waitForExistence(timeout: 10), "PIN key \(digit) missing")
            key.tap()
        }
        settle()
    }

    @MainActor
    @discardableResult
    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        settle()
        return true
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-seedSampleData",
            "-hideTips",
            // UserDefaults reads NSArgumentDomain, so these set the keys directly —
            // no app-side flag needed to keep the onboarding tour off the shots.
            "-feature_discovery_has_completed_tour", "YES",
            "-AppleLanguages", "(en)",
            // en_IE, not en_US: English copy but a euro locale, so the currency
            // picker matches the euro amounts the rest of the app hardcodes.
            "-AppleLocale", "en_IE",
        ]
        app.launch()
        return app
    }

    /// Screenshots are timing-sensitive: SwiftUI transitions and chart animations
    /// otherwise land mid-flight and the output stops being byte-stable between runs.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func shoot(_ name: String) throws {
        guard let outputDirectory else { return }
        settle()
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)")
        element.tap()
        settle()
    }

    @MainActor
    private func tapTab(_ app: XCUIApplication, _ label: String) {
        tap(app.tabBars.buttons[label])
    }

    /// The iPad shell's sidebar rows are collection-view cells, not buttons, so
    /// they are reached through their static text rather than app.buttons.
    @MainActor
    private func tapSidebar(_ app: XCUIApplication, _ label: String) {
        tap(app.collectionViews["Sidebar"].staticTexts[label].firstMatch)
    }

    @MainActor
    private func openProfile(_ app: XCUIApplication) {
        tap(app.buttons["Open profile"])
        // The sheet can lose the tap if a previous one is still dismissing.
        if !app.navigationBars["Settings"].waitForExistence(timeout: 5) {
            tap(app.buttons["Open profile"])
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings sheet never opened")
        }
        settle()
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        settle()
    }

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        for label in ["Close", "Cancel", "Done"] {
            let button = app.buttons[label].firstMatch
            if button.exists {
                button.tap()
                settle()
                return
            }
        }
        app.swipeDown(velocity: .fast)
        settle()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 6) {
        var remaining = attempts
        while !(element.exists && element.isHittable) && remaining > 0 {
            // Slow: a full-velocity swipe can fling straight past the target.
            app.swipeUp(velocity: .slow)
            remaining -= 1
        }
        settle()
    }
}
