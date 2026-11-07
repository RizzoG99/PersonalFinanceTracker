//
//  DismissTapTargetScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #266 and #267: the X on Home's spending callout and on the daily-reminder prompt must be
//  44 × 44 pt to tap without taking taps from what sits next to them. `-seedSpendingAnomaly`
//  makes the callout show on any date.
//

import XCTest

final class DismissTapTargetScenarioTests: ScenarioTestCase {

    /// Inside the new 44 pt area, and far enough out to miss the old one: at 15 pt the old
    /// button still took the tap on iPhone, so the scenario passed without the fix.
    private let besideTheGlyph = CGVector(dx: 0, dy: 20)

    @MainActor
    func testS1_calloutDismissPassesTheAudit() throws {
        let app = launchOnHome()
        let dismiss = reveal(app, app.buttons["Dismiss"])
        shoot(app, "S1")
        try auditAccessibility(app, "S1", screens: "Home")
        assertFullSizeTarget(dismiss)
    }

    @MainActor
    func testS2_tapBesideTheGlyphDismissesTheCallout() throws {
        let app = launchOnHome()
        let dismiss = reveal(app, app.buttons["Dismiss"])
        tapBesideGlyph(dismiss)
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5), "the callout stayed")
        XCTAssertTrue(app.scrollViews["homeDashboard"].isHittable, "the tap left Home")
        shoot(app, "S2")
    }

    @MainActor
    func testS3_tapOnTheMessageKeepsTheCallout() throws {
        let app = launchOnHome()
        let dismiss = reveal(app, app.buttons["Dismiss"])
        let message = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Warning'"))
            .firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "callout message not found")
        XCTAssertGreaterThanOrEqual(dismiss.frame.minX, message.frame.maxX - 0.5, "the target overlaps the message")
        // The first line, level with the X: at AX-XXXL the message's middle is under the tab bar.
        message.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0))
            .withOffset(CGVector(dx: -2, dy: 10))
            .tap()
        XCTAssertFalse(dismiss.waitForNonExistence(timeout: 2), "tapping the message dismissed the callout")
        shoot(app, "S3")
    }

    @MainActor
    func testS4_reminderDismissPassesTheAudit() throws {
        let app = launchOnHome()
        let dismiss = reveal(app, app.buttons["Dismiss reminder prompt"])
        shoot(app, "S4")
        try auditAccessibility(app, "S4", screens: "Home")
        assertFullSizeTarget(dismiss)
    }

    /// A regression guard, not the red test: the old button took this tap too. S4 is the red one.
    @MainActor
    func testS5_tapBesideTheGlyphDismissesTheReminderPrompt() throws {
        let app = launchOnHome()
        let dismiss = reveal(app, app.buttons["Dismiss reminder prompt"])
        tapBesideGlyph(dismiss)
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5), "the prompt stayed")
        XCTAssertTrue(app.scrollViews["homeDashboard"].isHittable, "the tap left Home")
        shoot(app, "S5")
    }

    /// A real tap as well as geometry: iOS gives a button taps outside its frame too, so frames
    /// alone can't show that Set keeps the taps on its edge. The X stealing one would dismiss the
    /// prompt for good. Set asks for notification permission, once per install.
    @MainActor
    func testS6_tapOnSetsEdgeLeavesThePrompt() throws {
        let app = launchOnHome()
        let dismiss = reveal(app, app.buttons["Dismiss reminder prompt"])
        let set = app.buttons["Set"]
        XCTAssertTrue(set.waitForExistence(timeout: 5), "Set button not found")
        XCTAssertGreaterThanOrEqual(dismiss.frame.minX, set.frame.maxX - 0.5, "the target covers Set")
        set.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -3, dy: 0))
            .tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            alert.buttons["Don’t Allow"].tap()
        }
        XCTAssertFalse(dismiss.waitForNonExistence(timeout: 2), "tapping Set dismissed the prompt")
        shoot(app, "S6")
    }

    // MARK: - Helpers

    @MainActor
    private func launchOnHome() -> XCUIApplication {
        let app = launchApp(["-seedSpendingAnomaly"])
        let home = app.scrollViews["homeDashboard"]
        XCTAssertTrue(home.waitForExistence(timeout: 30), "Home never appeared")
        // `launchApp` reopens a collapsed iPad sidebar, and it can close on its own while a tap is
        // in flight, moving Home's content from under it. Closing it first settles the layout.
        if UIDevice.current.userInterfaceIdiom == .pad {
            // By bar: Home's bar can show a second "Hide Sidebar" button.
            app.navigationBars["Finance"].buttons["Hide Sidebar"].tap()
            XCTAssertTrue(app.collectionViews["Sidebar"].waitForNonExistence(timeout: 5), "sidebar stayed open")
        }
        return app
    }

    /// Scrolls Home until `element` is on screen, and far enough above the tab bar for a tap beside
    /// it: iPhone keeps the reminder prompt below the fold, and at AX-XXXL a tap that lands on the
    /// tab bar leaves Home, which makes the button "disappear" without being pressed.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) -> XCUIElement {
        let home = app.scrollViews["homeDashboard"]
        let bottomLimit = UIDevice.current.userInterfaceIdiom == .pad ? CGFloat.infinity : app.tabBars.firstMatch.frame.minY
        func isReady() -> Bool {
            element.waitForExistence(timeout: 2) && element.isHittable && element.frame.midY + besideTheGlyph.dy + 4 < bottomLimit
        }
        for _ in 0..<16 where !isReady() {
            scrollUp(home)
        }
        XCTAssertTrue(isReady(), "\(element) never came clear of the tab bar")
        waitForStableFrame(element)
        return element
    }

    /// These tests tap a fixed distance from the button, so it must have stopped moving.
    @MainActor
    private func waitForStableFrame(_ element: XCUIElement) {
        var last = element.frame
        for _ in 0..<10 {
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "layout settles")], timeout: 0.5)
            let frame = element.frame
            if frame == last { return }
            last = frame
        }
        XCTFail("\(element) never stopped moving")
    }

    @MainActor
    private func assertFullSizeTarget(_ element: XCUIElement) {
        // 0.01 absorbs floating-point noise: an exact 44 pt frame reads back as 43.99999999999994.
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.99)
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.99)
    }

    @MainActor
    private func tapBesideGlyph(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(besideTheGlyph)
            .tap()
    }
}
