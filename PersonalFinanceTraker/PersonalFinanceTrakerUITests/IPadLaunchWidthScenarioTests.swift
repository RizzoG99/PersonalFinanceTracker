//
//  IPadLaunchWidthScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #358: on the second launch after install, iPadOS laid the split view out at 448 pt instead of
//  the window's width, and sometimes it stayed there: Home in one narrow column, the right half
//  empty. An `.inspector` attached to the whole split view caused it, closed or not.
//
//  Container frames can't show it: the window and `homeDashboard` report full width even then.
//  The Hide amounts button at the trailing edge of Home's bar does, so the tests measure that.
//
//  S1 reproduces only on the second launch after an install. `scripts/xcb scenarios` reinstalls
//  once per pass, so S1 is red-capable only when this class runs on its own:
//  `scripts/xcb scenarios IPadLaunchWidthScenarioTests`. In the regression run it is a guard.
//

import XCTest

final class IPadLaunchWidthScenarioTests: ScenarioTestCase {

    @MainActor
    func testS1_secondLaunchFillsTheWindow() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only: iPhone has no split view")
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments(hideTips: true)
        app.launch()
        XCTAssertTrue(app.scrollViews["homeDashboard"].waitForExistence(timeout: 30), "Home never appeared")
        app.terminate()

        app.launch()
        XCTAssertTrue(app.scrollViews["homeDashboard"].waitForExistence(timeout: 30), "Home never appeared")
        assertHomeReachesTrailingEdge(app)
        shoot(app, "S1")
    }

    @MainActor
    func testS2_closingTheSidebarKeepsHomeFullWidth() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only: iPhone has no split view")
        let app = launchApp()
        XCTAssertTrue(app.scrollViews["homeDashboard"].waitForExistence(timeout: 30), "Home never appeared")
        // By bar: Home's bar can show a second "Hide Sidebar" button. The sidebar's bar has no
        // title (#219), so it's the one holding "Scan receipt".
        app.navigationBars.containing(.button, identifier: "Scan receipt").buttons["Hide Sidebar"].tap()
        XCTAssertTrue(app.collectionViews["Sidebar"].waitForNonExistence(timeout: 5), "sidebar stayed open")
        assertHomeReachesTrailingEdge(app)
        shoot(app, "S2")
    }

    /// Normally the button ends within 20 pt of the window's edge (826 of 834 in portrait). In the
    /// bug it ended at 440.
    @MainActor
    private func assertHomeReachesTrailingEdge(_ app: XCUIApplication) {
        let hide = app.navigationBars["Home"].buttons["Hide amounts"]
        XCTAssertTrue(hide.waitForExistence(timeout: 10), "Home's Hide amounts button not found")
        let window = app.windows.firstMatch.frame
        // Settles first: after the sidebar closes, the bar slides into place.
        var maxX = hide.frame.maxX
        for _ in 0..<10 {
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "layout settles")], timeout: 0.5)
            if hide.frame.maxX == maxX { break }
            maxX = hide.frame.maxX
        }
        XCTAssertGreaterThan(maxX, window.maxX - 20, "Home ends at \(maxX) pt in a \(window.width) pt window (#358)")
    }
}
