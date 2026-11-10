//
//  RecurringDeleteScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #253: swipe-deleting a recurring rule must not crash. Scenarios S1–S4 are the acceptance
//  contract in the issue. `-seedRecurringRules` gives each test its rules, with a linked
//  transaction, so the tests don't depend on what another one left behind.
//

import XCTest

final class RecurringDeleteScenarioTests: ScenarioTestCase {

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor
    func testS1_deleteSecondOfTwoRules() throws {
        let app = launchApp(["-seedRecurringRules", "2"])
        openRecurring(app)
        XCTAssertTrue(app.staticTexts["2"].waitForExistence(timeout: 10), "Active doesn't count two rules")
        let ruleA = row(app, "Rule A")
        let ruleB = row(app, "Rule B")
        scrollUntilHittable(app, ruleA, ruleB)

        // Same next date, so `fetchAllRecurrenceRules` puts them in name order (#366).
        XCTAssertLessThan(ruleA.frame.minY, ruleB.frame.minY, "Rule A isn't above Rule B")
        swipeDelete(app, ruleB)

        XCTAssertTrue(ruleB.waitForNonExistence(timeout: 10), "the deleted rule is still listed")
        XCTAssertEqual(app.state, .runningForeground, "the app crashed")
        XCTAssertTrue(ruleA.exists, "the other rule left too")
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 5), "Active doesn't show 1")
        shoot(app, "S1")
        try auditAccessibility(app, "S1", screens: "Recurring")
    }

    @MainActor
    func testS2_deleteOnlyRule() throws {
        let app = launchApp(["-seedRecurringRules", "1"])
        openRecurring(app)
        let rule = row(app, "Rule A")
        scrollUntilHittable(app, rule)

        swipeDelete(app, rule)

        XCTAssertTrue(app.staticTexts["No recurring transactions yet"].waitForExistence(timeout: 10), "no empty state")
        XCTAssertEqual(app.state, .runningForeground, "the app crashed")
        shoot(app, "S2")
        try auditAccessibility(app, "S2", screens: "Recurring")
    }

    @MainActor
    func testS3_deletedRuleStaysGoneAndKeepsHistory() throws {
        let app = launchApp(["-seedRecurringRules", "2"])
        openRecurring(app)
        let ruleA = row(app, "Rule A")
        scrollUntilHittable(app, ruleA)
        swipeDelete(app, ruleA)
        XCTAssertTrue(ruleA.waitForNonExistence(timeout: 10), "the deleted rule is still listed")

        leaveRecurring(app)
        if isPad { app.collectionViews["Sidebar"].staticTexts["Home"].tap() }
        openRecurring(app)
        scrollUntilHittable(app, row(app, "Rule B"))
        XCTAssertFalse(ruleA.exists, "the deleted rule came back")

        leaveRecurring(app)
        openActivity(app)
        let history = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Rule A"))
            .firstMatch
        // At the largest text sizes Activity's summary cards push today's rows off the first screen.
        scrollUntilHittable(app, history)
        shoot(app, "S3")
    }

    @MainActor
    func testS4_remainingRuleStillOpensEdit() throws {
        let app = launchApp(["-seedRecurringRules", "2"])
        openRecurring(app)
        let ruleA = row(app, "Rule A")
        let ruleB = row(app, "Rule B")
        scrollUntilHittable(app, ruleA, ruleB)
        swipeDelete(app, ruleA)
        XCTAssertTrue(ruleA.waitForNonExistence(timeout: 10), "the deleted rule is still listed")

        ruleB.tap()

        XCTAssertTrue(app.navigationBars["Edit Recurring"].waitForExistence(timeout: 10), "the edit form didn't open")
        shoot(app, "S4")
    }

    // MARK: - Steps

    /// The row's `Button` combines its texts, so the label holds the title among other things.
    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// At the largest text sizes the stat cards fill the first screen and the list is lazy, so a
    /// rule's row exists only once scrolled to.
    @MainActor
    private func scrollUntilHittable(_ app: XCUIApplication, _ rows: XCUIElement...) {
        for _ in 0..<5 {
            if rows.allSatisfy({ $0.waitForExistence(timeout: 2) && $0.isHittable }) { return }
            app.swipeUp()
        }
        XCTFail("\(rows) never became hittable")
    }

    @MainActor
    private func openRecurring(_ app: XCUIApplication) {
        if isPad {
            app.collectionViews["Sidebar"].staticTexts["Recurring"].firstMatch.tap()
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar never appeared")
            app.tabBars.buttons["Plan"].tap()
            let seeAll = app.buttons["See all"].firstMatch
            XCTAssertTrue(seeAll.waitForExistence(timeout: 10), "Plan has no See all")
            seeAll.tap()
        }
    }

    /// iPhone only: Recurring is a sheet there, and a permanent pane on iPad.
    @MainActor
    private func leaveRecurring(_ app: XCUIApplication) {
        guard !isPad else { return }
        let close = app.buttons["Close"]
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "the Recurring sheet didn't close")
    }

    @MainActor
    private func openActivity(_ app: XCUIApplication) {
        if isPad {
            app.collectionViews["Sidebar"].staticTexts["Activity"].firstMatch.tap()
        } else {
            app.tabBars.buttons["Activity"].tap()
        }
    }

    /// A long swipe may already fire the action; a short one leaves the Delete button showing.
    /// A swipe can also do nothing (seen on iPad while the sidebar overlay leaves), so it repeats.
    @MainActor
    private func swipeDelete(_ app: XCUIApplication, _ row: XCUIElement) {
        let delete = app.buttons["Delete"]
        for _ in 0..<3 {
            row.swipeLeft()
            if delete.waitForExistence(timeout: 2), delete.isHittable {
                delete.tap()
                return
            }
            if row.waitForNonExistence(timeout: 1) { return }
        }
    }
}
