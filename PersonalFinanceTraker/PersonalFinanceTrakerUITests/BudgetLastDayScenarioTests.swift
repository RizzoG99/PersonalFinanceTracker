//
//  BudgetLastDayScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #342: spending on a pay cycle's last day counts toward its budget. Scenarios S1–S2 are the
//  acceptance contract in the issue. The Add form refuses future dates, so the expense is
//  seeded (`-seedBudgetBoundaryExpense`) rather than typed: on any day but the last, the
//  cycle's last day is still ahead.
//

import XCTest

final class BudgetLastDayScenarioTests: ScenarioTestCase {

    @MainActor
    func testS1_lastDayExpenseCountsTowardBudget() throws {
        let app = launchApp(["-seedBudgetBoundaryExpense", "lastDay"])
        // €100 against Streaming's €40 budget: over 80 %, so Home's budget card lists it.
        XCTAssertTrue(scrollHomeUntilExists(app, budgetBar(app, "Streaming Services")),
                      "the last day's expense is not counted toward Streaming Services' budget")
        shoot(app, "S1")
        try auditAccessibility(app, "S1", screens: "Home")
    }

    @MainActor
    func testS2_nextCycleExpenseDoesNotCount() throws {
        let app = launchApp(["-seedBudgetBoundaryExpense", "nextCycle"])
        // Control: proves the budget card rendered and is scrolled into view, so the absence
        // below means "not counted", not "not on screen yet".
        let control = budgetBar(app, "Clothing")
        // Once on ipad-light the bar was on screen yet never reported hittable (not reproduced
        // since); the state goes into the message so the next occurrence says which.
        XCTAssertTrue(scrollHomeUntilExists(app, control),
                      "control budget bar never showed (exists \(control.exists), hittable \(control.exists && control.isHittable))")
        XCTAssertFalse(budgetBar(app, "Streaming Services").exists,
                       "the next cycle's expense is counted toward this cycle's budget")
        shoot(app, "S2")
        try auditAccessibility(app, "S2", screens: "Home")
    }

    // MARK: - Steps

    /// `BudgetProgressBarView` combines its children into "<category>, €spent of €budget…".
    /// " of " matters: the seeded expense has no name, so its Recent Transactions row is also
    /// titled "<category>, …" and matched a bare prefix (a vacuous S1 pass on today's code).
    private func budgetBar(_ app: XCUIApplication, _ category: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS ' of '", "\(category),"))
            .firstMatch
    }

    /// Scrolls Home until `element` is on screen. iPad's budget card is a LazyVGrid at the bottom
    /// of Home: its rows exist only once on screen.
    @MainActor
    private func scrollHomeUntilExists(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        let home = app.scrollViews["homeDashboard"]
        XCTAssertTrue(home.waitForExistence(timeout: 30), "Home never appeared")
        // `launchApp` reopens a collapsed iPad sidebar; in portrait it then overlays Home and
        // hides Home's content from queries. Choosing Home in it dismisses the overlay.
        if UIDevice.current.userInterfaceIdiom == .pad, !home.isHittable {
            app.collectionViews["Sidebar"].staticTexts["Home"].tap()
            let uncovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: home)
            XCTAssertEqual(XCTWaiter().wait(for: [uncovered], timeout: 5), .completed, "sidebar still covers Home")
        }
        // Hittable, not just existing: iPhone's Home is not lazy, so the bar exists off screen,
        // and the screenshot must show it.
        for _ in 0..<16 {
            if element.waitForExistence(timeout: 2), element.isHittable { return true }
            scrollUp(home)
        }
        return element.waitForExistence(timeout: 5) && element.isHittable
    }
}
