//
//  ToolbarIconStyleScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #257: on iPhone the top-bar icons of the tab screens share one neutral colour, like the
//  unselected tab icons, and + is the one prominent action (filled indigo, white glyph).
//  Colour is measured from pixels, with the helpers in ToolbarPixels.swift.
//

import XCTest

final class ToolbarIconStyleScenarioTests: ScenarioTestCase {

    /// S1 — Home: gear and Scan receipt draw in the same neutral colour, + is prominent.
    @MainActor
    func testS1_homeToolbarIconsMatch() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Per-screen toolbar items are iPhone-only")
        let app = launchApp(["-unseenReleaseFixture"])
        let bar = app.navigationBars.firstMatch
        let gear = try gearTarget(bar), scan = try button(bar, "Scan receipt"), add = try button(bar, "Add transaction")
        // Before the colour checks, so the run on unchanged code still leaves its baseline picture.
        shoot(app, "S1")
        try assertSameNeutral([("gear", gear), ("Scan receipt", whole(scan))])
        try assertProminent(add)
        try auditAccessibility(app, "S1", screens: "Home")
    }

    /// S2 — Activity: gear, Travels and Scan receipt draw in the same neutral colour, + is prominent.
    @MainActor
    func testS2_activityToolbarIconsMatch() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Per-screen toolbar items are iPhone-only")
        let app = launchApp(["-unseenReleaseFixture"])
        let activity = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activity.waitForExistence(timeout: 30), "Activity tab missing")
        activity.tap()
        let bar = app.navigationBars["Activity"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Activity never appeared")
        let gear = try gearTarget(bar), travels = try button(bar, "Travels")
        let scan = try button(bar, "Scan receipt"), add = try button(bar, "Add transaction")
        shoot(app, "S2")
        try assertSameNeutral([("gear", gear), ("Travels", whole(travels)), ("Scan receipt", whole(scan))])
        try assertProminent(add)
        try auditAccessibility(app, "S2", screens: "Activity")
    }

    /// S3 — the new-release dot on the gear still shows in indigo.
    @MainActor
    func testS3_newReleaseDotStaysIndigo() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Per-screen toolbar items are iPhone-only")
        let app = launchApp(["-unseenReleaseFixture"])
        let gear = try gearWithDot(app.navigationBars.firstMatch)
        shoot(app, "S3")
        // A share of indigo pixels, not the ink: the corner also holds gear teeth, which differ
        // from the background more than the dot does in dark mode.
        let share = try settled { try self.indigoShare(gear, crop: CGRect(x: 0.6, y: 0, width: 0.4, height: 0.4)) }
        XCTAssertGreaterThan(share, 0.02, "the dot should show in indigo, indigo share of the corner \(share)")
    }

    /// S4 — iPad: the shell keeps its own toolbar and sidebar; no per-screen gear appears.
    /// The shell's own icon style is #408's, checked in IPadToolbarIconStyleScenarioTests.
    @MainActor
    func testS4_iPadShellUnchanged() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad shell only")
        let app = launchApp(["-unseenReleaseFixture"])
        XCTAssertTrue(app.buttons["Add transaction"].firstMatch.waitForExistence(timeout: 30), "shell Add missing")
        XCTAssertFalse(app.navigationBars.buttons["Open profile"].waitForExistence(timeout: 2), "per-screen gear leaked onto iPad")
        shoot(app, "S4")
        try auditAccessibility(app, "S4", screens: "Home")
    }

    // MARK: - Targets

    @MainActor
    private func button(_ bar: XCUIElement, _ label: String) throws -> XCUIElement {
        let button = bar.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(label) missing")
        return button
    }

    /// The gear once its dot shows, so the dot is in the same place on every run.
    @MainActor
    private func gearWithDot(_ bar: XCUIElement) throws -> XCUIElement {
        let gear = try button(bar, "Open profile")
        let new = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'New'"), object: gear)
        XCTAssertEqual(XCTWaiter().wait(for: [new], timeout: 15), .completed, "precondition: the fixture release should be unseen")
        return gear
    }

    /// The gear without its top-trailing corner, where the indigo dot sits.
    @MainActor
    private func gearTarget(_ bar: XCUIElement) throws -> Target {
        Target(element: try gearWithDot(bar), crop: CGRect(x: 0, y: 0.35, width: 0.65, height: 0.65))
    }
}
