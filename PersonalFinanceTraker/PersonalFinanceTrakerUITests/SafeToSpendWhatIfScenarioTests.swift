//
//  SafeToSpendWhatIfScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #213: "What if I spend €X today?" on the Safe to Spend hero. The answer reads like the hero
//  ("€…, until …"), so the checks count those readings before and after typing an amount
//  rather than depending on what SampleData leaves to spend.
//

import XCTest

final class SafeToSpendWhatIfScenarioTests: ScenarioTestCase {

    /// A small spend adds a second "until …" reading under the hero.
    @MainActor
    func testS1_smallSpendShowsWhatIsLeft() throws {
        let app = openWhatIf()
        // The hero alone can match more than once (its group and its text), so compare counts.
        let before = readings(app, containing: "until ").count
        XCTAssertGreaterThan(before, 0, "no hero reading to compare against")
        type("1", in: app)
        let after = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.readings(app, containing: "until ").count > before },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [after], timeout: 5), .completed, "typing an amount showed no what-if result")
        shoot(app, "S1")
        dismissKeyboard(app)
        try auditAccessibility(app, "S1", screens: "Home")
    }

    /// A spend far beyond the plan reads as over plan, and nothing was recorded.
    @MainActor
    func testS2_hugeSpendReadsOverPlan() throws {
        let app = openWhatIf()
        let overBefore = readings(app, containing: "Over plan until").count
        type("1000000", in: app)
        let overAfter = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.readings(app, containing: "Over plan until").count > overBefore },
            object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [overAfter], timeout: 5), .completed, "€1,000,000 today did not read as over plan")
        shoot(app, "S2")
        dismissKeyboard(app)
        try auditAccessibility(app, "S2", screens: "Home")
    }

    // MARK: - Steps

    @MainActor
    private func openWhatIf() -> XCUIApplication {
        let app = launchApp()
        let home = app.scrollViews["homeDashboard"]
        XCTAssertTrue(home.waitForExistence(timeout: 30), "Home never appeared")
        // In iPad portrait the reopened sidebar overlays Home (see BudgetLastDayScenarioTests).
        if UIDevice.current.userInterfaceIdiom == .pad, !home.isHittable {
            app.collectionViews["Sidebar"].staticTexts["Home"].tap()
        }
        let toggle = app.buttons["What if I spend…"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no What if row on the hero (does SampleData have income this cycle?)")
        toggle.tap()
        XCTAssertTrue(app.textFields["whatIfAmount"].waitForExistence(timeout: 5), "the What if row didn't expand")
        return app
    }

    @MainActor
    private func type(_ amount: String, in app: XCUIApplication) {
        let field = app.textFields["whatIfAmount"]
        field.tap()
        field.typeText(amount)
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Done left the keyboard up")
    }

    /// The hero and the what-if result each combine into one element: "€…, until …".
    @MainActor
    private func readings(_ app: XCUIApplication, containing text: String) -> XCUIElementQuery {
        app.scrollViews["homeDashboard"].descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS '€'", text))
    }
}
