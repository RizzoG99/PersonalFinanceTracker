//
//  HarnessRetryProbe.swift
//  PersonalFinanceTrakerUITests
//
//  #278: checks `scripts/xcb scenarios`' retry and flaky reporting, not the app. Fails on
//  purpose, so the file name stays outside the `*ScenarioTests.swift` regression glob. Run
//  one test at a time:
//    scripts/xcb scenarios HarnessRetryProbe/testS1_failsOnceThenPasses  # Passed, listed in "flaky"
//    scripts/xcb scenarios HarnessRetryProbe/testS2_failsEveryAttempt    # Failed
//

import XCTest

final class HarnessRetryProbe: ScenarioTestCase {

    /// A retry runs in the same test process, so this survives into it; each pass starts at 0.
    @MainActor static var attempts = 0

    @MainActor
    func testS1_failsOnceThenPasses() {
        Self.attempts += 1
        XCTAssertGreaterThan(Self.attempts, 1, "first attempt fails on purpose")
    }

    func testS2_failsEveryAttempt() {
        XCTFail("fails every attempt on purpose")
    }
}
