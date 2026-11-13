//
//  IPadToolbarIconStyleScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #408: on iPad the shell toolbar's secondary icons (sidebar toggle, Scan receipt, Hide
//  amounts) share one neutral colour and + is the one prominent action, as on iPhone (#257).
//  Colour is measured from pixels, with the helpers in ToolbarPixels.swift. Every button is
//  found through its own bar: Home's balance card also says "Hide amounts", and Home's bar
//  can show a second "Hide Sidebar".
//

import XCTest

final class IPadToolbarIconStyleScenarioTests: ScenarioTestCase {

    /// S1 — sidebar toggle, Scan receipt and the eye draw in one neutral colour, + is prominent,
    /// in portrait and again in landscape.
    @MainActor
    func testS1_shellToolbarIconsMatch() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad shell only")
        let app = launchApp()
        try assertShellToolbar(app, "S1")
        try auditAccessibility(app, "S1", screens: "Home")
        XCUIDevice.shared.orientation = .landscapeLeft
        try assertShellToolbar(app, "S1L")
    }

    /// S2 — after tapping the eye, amounts hide and eye.slash stays neutral.
    @MainActor
    func testS2_toggledEyeStaysNeutral() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad shell only")
        let app = launchApp()
        let toggle = existing(sidebarBar(app).buttons["Hide Sidebar"])
        existing(homeBar(app).buttons["Hide amounts"]).tap()
        // The label flips only once the setting is on, so this is the "amounts hidden" precondition.
        let slash = existing(homeBar(app).buttons["Show amounts"])
        shoot(app, "S2")
        try assertSameNeutral([("sidebar toggle", whole(toggle)), ("Show amounts", whole(slash))])
    }

    /// S3 — the selected sidebar row (Home) still highlights in indigo: the shell tint is kept.
    /// The row is filled with the tint, so most of the cell is indigo; 0.02 only rules out "no tint".
    @MainActor
    func testS3_sidebarSelectionStaysIndigo() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad shell only")
        let app = launchApp()
        let home = existing(app.collectionViews["Sidebar"].cells.containing(NSPredicate(format: "label == 'Home'")).firstMatch)
        XCTAssertTrue(home.isSelected, "precondition: Home should be the selected sidebar row")
        shoot(app, "S3")
        let share = try settled { try self.indigoShare(home) }
        XCTAssertGreaterThan(share, 0.02, "the selected row should highlight in indigo, indigo share \(share)")
    }

    // MARK: - Helpers

    /// Shoots first, so a run on unchanged code still leaves its baseline picture.
    @MainActor
    private func assertShellToolbar(_ app: XCUIApplication, _ scenario: String) throws {
        let bar = sidebarBar(app)
        let toggle = existing(bar.buttons["Hide Sidebar"]), scan = existing(bar.buttons["Scan receipt"])
        let add = existing(bar.buttons["Add transaction"]), eye = existing(homeBar(app).buttons["Hide amounts"])
        shoot(app, scenario)
        try assertSameNeutral([("sidebar toggle", whole(toggle)), ("Scan receipt", whole(scan)), ("Hide amounts", whole(eye))])
        try assertProminent(add)
    }

    @MainActor
    private func sidebarBar(_ app: XCUIApplication) -> XCUIElement { app.navigationBars["Finance"] }

    @MainActor
    private func homeBar(_ app: XCUIApplication) -> XCUIElement { app.navigationBars["Home"] }

    @MainActor
    private func existing(_ element: XCUIElement) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(element) missing")
        return element
    }
}
