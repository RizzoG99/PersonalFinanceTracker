//
//  DynamicTypeScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #219: at accessibility text sizes the Financial Pulse quick-log buttons show their full
//  amount (stacked under the label), and the iPad sidebar rows scale and aren't clipped.
//  The text size is forced per test with a launch argument, so every pass checks the size
//  its scenario names; the pass still decides light or dark.
//

import XCTest

final class DynamicTypeScenarioTests: ScenarioTestCase {

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private static let accessibilitySize = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    private static let defaultSize = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
    /// `-seedPendingCheckIn`'s two quick-log habits and their amounts.
    private static let habits = [("Log Morning coffee", "-€3.50"), ("Log Bus ticket", "-€2.00")]

    @MainActor
    func testS1_quickLogAmountsFitAtAccessibilitySize() throws {
        let app = launchApp(["-seedPendingCheckIn"] + Self.accessibilitySize)
        if isPad {
            // Sidebar hidden: its known AX findings (#400) are exempt in every audit while it shows,
            // and this scenario is about Home's content. S3 covers the sidebar.
            XCTAssertTrue(app.scrollViews["homeDashboard"].waitForExistence(timeout: 60), "Home never appeared")
            app.navigationBars.containing(.button, identifier: "Scan receipt").buttons["Hide Sidebar"].tap()
            XCTAssertTrue(app.collectionViews["Sidebar"].waitForNonExistence(timeout: 5), "sidebar stayed open")
        }
        var frames: [(name: String, label: CGRect, amount: CGRect, button: CGRect)] = []
        // At AX-XXXL the two buttons may not share a screen: audit each one while it is in view.
        for (label, amount) in Self.habits {
            frames.append(try quickLogFrames(app, label, amount))
            // Shot while the last button is in view: the audit can leave the screen scrolled elsewhere.
            if label == Self.habits.last?.0 { shoot(app, "S1") }
            try auditAccessibility(app, "S1", screens: "Home")
        }
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.amount.minY, frame.label.maxY - 1, "S1: '\(frame.name)' amount isn't stacked under its label")
            XCTAssertTrue(frame.button.insetBy(dx: -1, dy: -1).contains(frame.amount), "S1: '\(frame.name)' amount spills out of its button")
        }
    }

    @MainActor
    func testS2_quickLogStaysOneRowAtDefaultSize() throws {
        let app = launchApp(["-seedPendingCheckIn"] + Self.defaultSize)
        var frames: [(name: String, label: CGRect, amount: CGRect, button: CGRect)] = []
        for (label, amount) in Self.habits {
            frames.append(try quickLogFrames(app, label, amount))
        }
        shoot(app, "S2")
        for frame in frames {
            XCTAssertLessThan(abs(frame.amount.midY - frame.label.midY), 4, "S2: '\(frame.name)' amount left its label's row")
            XCTAssertLessThan(frame.button.maxX - frame.amount.maxX, 40, "S2: '\(frame.name)' amount isn't at the trailing edge")
        }
        try auditAccessibility(app, "S2", screens: "Home")
    }

    @MainActor
    func testS3_sidebarReadableAtAccessibilitySize() throws {
        try XCTSkipUnless(isPad, "iPad only: iPhone has no sidebar")
        let app = launchApp(Self.accessibilitySize)
        let sidebar = app.collectionViews["Sidebar"]
        XCTAssertTrue(sidebar.staticTexts["Home"].waitForExistence(timeout: 30), "S3: sidebar has no 'Home' row")
        shoot(app, "S3")
        try auditAccessibility(app, "S3", screens: "Home")
        // Rows below the fold: every scroll reveals a new viewport, so each one gets its own audit.
        let titles: Set = ["Home", "Activity", "Recurring", "Budgets", "Goals", "Insights", "Health Score", "Settings"]
        let window = app.windows.firstMatch.frame
        func fullyVisible() -> Set<String> {
            titles.filter { title in
                let row = sidebar.staticTexts[title].firstMatch
                return row.exists && row.isHittable && window.contains(row.frame)
            }
        }
        var seen = fullyVisible()
        for _ in 0..<8 where seen != titles {
            scrollUp(sidebar)
            try auditAccessibility(app, "S3", screens: "Home")
            seen.formUnion(fullyVisible())
        }
        XCTAssertEqual(seen, titles, "S3: sidebar rows never fully on screen: \(titles.subtracting(seen).sorted())")
    }

    @MainActor
    func testS4_settingsShowsNewBadge() throws {
        try XCTSkipUnless(isPad, "iPad only: iPhone has no sidebar")
        // Pins an unseen release: otherwise the badge depends on the remote manifest and the app version.
        let app = launchApp(["-unseenReleaseFixture"])
        let settingsRow = app.collectionViews["Sidebar"].cells.containing(.staticText, identifier: "Settings").firstMatch
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 10), "S4: no Settings row in the sidebar")
        XCTAssertTrue(settingsRow.staticTexts["New"].waitForExistence(timeout: 10), "S4: the Settings row shows no 'New' badge with an unseen release")
        shoot(app, "S4")
        try auditAccessibility(app, "S4", screens: "Home")
    }

    // MARK: - Steps

    /// Scrolls the quick-log button fully on screen and returns its label, amount and button frames.
    @MainActor
    private func quickLogFrames(_ app: XCUIApplication, _ label: String, _ amount: String) throws -> (name: String, label: CGRect, amount: CGRect, button: CGRect) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", label)
        let button = app.buttons.matching(predicate).firstMatch
        // 60 s: a pass's first launch after a simulator cold boot can stall the main thread 30 s+ (#341).
        XCTAssertTrue(button.waitForExistence(timeout: 60), "Financial Pulse isn't pending with quick templates")
        let scrollView = app.scrollViews.containing(predicate).firstMatch
        let window = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 40)
        for _ in 0..<30 where !(button.isHittable && window.contains(button.frame)) {
            scrollUp(scrollView)
        }
        XCTAssertTrue(window.contains(button.frame), "'\(label)' never came fully on screen")
        let labelText = button.staticTexts[label].firstMatch
        let amountText = button.staticTexts[amount].firstMatch
        XCTAssertTrue(labelText.waitForExistence(timeout: 5), "'\(label)' has no label text")
        XCTAssertTrue(amountText.waitForExistence(timeout: 5), "'\(label)' has no amount text '\(amount)'")
        return (label, labelText.frame, amountText.frame, button.frame)
    }
}
