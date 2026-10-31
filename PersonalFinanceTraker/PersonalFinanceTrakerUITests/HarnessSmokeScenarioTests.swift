//
//  HarnessSmokeScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  Proves the scenario harness itself: a clean install opens straight on Home.
//

import XCTest

final class HarnessSmokeScenarioTests: ScenarioTestCase {

    @MainActor
    func testS0_cleanInstallOpensOnHome() throws {
        let app = launchApp()
        let home = UIDevice.current.userInterfaceIdiom == .pad
            ? app.collectionViews["Sidebar"]
            : app.tabBars.firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30), "Home never appeared")
        shoot(app, "S0")
        try auditAccessibility(app, "S0", screens: "Home")
    }
}
