//
//  PersonalFinanceTrakerUITests.swift
//  PersonalFinanceTrakerUITests
//
//  Created by Gabriele Rizzo on 03/09/25.
//

import XCTest

final class PersonalFinanceTrakerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.

        // Must be set here, not inside the test body: the allowance is read when the case
        // starts, so assigning it later is ignored and the default 2 minutes still applies.
        // See testLaunchPerformance for why the default is not enough locally.
        executionTimeAllowance = 300
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Measured on this repo's simulator: the UI-test harness costs ~17s per case
        // before any launch happens, and each measured launch adds ~10-15s. The default
        // five iterations therefore sit right on the 2-minute execution allowance — CI's
        // hardware slips under it, a developer's machine does not, and the test then fails
        // for a reason that has nothing to do with launch performance. Three iterations
        // with a generous allowance keeps the metric and stops the false alarm.
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let app = XCUIApplication()
            // Measure the app, not its first-run gates. Without these, every iteration
            // pays for PIN setup, the onboarding tour and TipKit — ~7s of onboarding
            // recorded as launch time, and a number that changes once you have a PIN.
            app.launchArguments = [
                "-pin_setup_complete", "YES",
                "-hideTips",
                "-feature_discovery_has_completed_tour", "YES",
            ]
            app.launch()
        }
    }
}
