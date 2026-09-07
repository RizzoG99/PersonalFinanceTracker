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

    /// Launch budget, in seconds, for the median of three warm launches on a simulator.
    ///
    /// Deliberately loose, and it has to be. This times `app.launch()` from the test's side,
    /// so it includes what XCUITest does around the launch — terminate, relaunch, wait for
    /// the app to go idle — not just the app's own startup. Observed warm medians here are
    /// 9-14s, against the 3.4s that XCTApplicationLaunchMetric attributes to the app itself.
    ///
    /// So this catches a launch that has become several times slower — a blocking call added
    /// to startup, a container migration running on every open — and nothing subtler. A tight
    /// bound on a machine that also runs Xcode, a simulator and a build would fail for reasons
    /// that have nothing to do with this app, which is exactly the flake this replaced.
    static let launchBudget: TimeInterval = 25

    @MainActor
    func testLaunchPerformance() throws {
        // Times launches directly instead of `measure(metrics: [XCTApplicationLaunchMetric()])`.
        //
        // Two reasons that mechanism did not work here. Its three iterations of identical code
        // measured 15.06s, 10.86s and 3.36s — the first launch after an install pays for cold
        // caches, and averaging that with warm launches produces a number no threshold can be
        // set against. And XCTest baselines are keyed by run-destination UUID, while `xcb`
        // creates a per-worktree simulator with a fresh UDID, so a recorded baseline would match
        // no other machine, not CI, and not this worktree after `xcb delete-sim` — XCTest finds
        // no baseline for the destination and silently checks nothing.
        //
        // The wall clock is also very different: `measure` spent 90-300s on the settle it
        // inserts between iterations, which is what kept taking the release down with it.
        let app = XCUIApplication()
        app.launchArguments = [
            // Measure the app, not its first-run gates. Without these every launch pays for
            // PIN setup, the onboarding tour and TipKit — onboarding recorded as launch time,
            // and a number that changes once you have a PIN.
            "-pin_setup_complete", "YES",
            "-hideTips",
            "-feature_discovery_has_completed_tour", "YES",
        ]

        // Warm-up, not measured: this is the 15s one.
        app.launch()
        app.terminate()

        var durations: [TimeInterval] = []
        for _ in 0..<3 {
            let start = Date()
            app.launch()
            durations.append(Date().timeIntervalSince(start))
            app.terminate()
        }

        // Median, so one hiccup from an unrelated process does not fail the run.
        let median = durations.sorted()[1]
        let formatted = durations.map { String(format: "%.2fs", $0) }.joined(separator: ", ")
        XCTContext.runActivity(named: "Warm launches: \(formatted)") { _ in }

        XCTAssertLessThan(
            median,
            Self.launchBudget,
            "Median warm launch was \(String(format: "%.2f", median))s against a \(Self.launchBudget)s budget (all: \(formatted))"
        )
    }
}
