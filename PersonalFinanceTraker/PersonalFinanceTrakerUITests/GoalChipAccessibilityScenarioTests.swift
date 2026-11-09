//
//  GoalChipAccessibilityScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #361: goal chips in Add Transaction are buttons and expose their selected state, like the
//  category chips in #270.
//

import XCTest

final class GoalChipAccessibilityScenarioTests: ScenarioTestCase {

    @MainActor
    func testS1_chipsAreSelectableButtons() throws {
        let app = launchApp(["-seedGoalProjections", "YES"])
        openTransfer(app)
        let labels = strip(app).buttons.allElementsBoundByIndex.map(\.label)
        let firstName = try XCTUnwrap(labels.first, "no goal button in the strip")
        let secondName = try XCTUnwrap(labels.dropFirst().first, "only one goal button in the strip")
        let first = strip(app).buttons[firstName]
        let second = strip(app).buttons[secondName]

        first.tap()
        assertSelected(first, true, "first chip not selected after tapping it")
        second.tap()
        assertSelected(second, true, "second chip not selected after tapping it")
        assertSelected(first, false, "first chip still selected after picking another")
        shoot(app, "S1")
        try auditAccessibility(app, "S1", screens: "AddTransaction", "Home")
    }

    @MainActor
    func testS2_swipingStripSelectsNothing() throws {
        let app = launchApp(["-seedGoalProjections", "YES"])
        openTransfer(app)
        let selected = strip(app).buttons.matching(NSPredicate(format: "selected == true"))
        let before = selected.allElementsBoundByIndex.map(\.label)

        strip(app).swipeLeft()
        XCTAssertEqual(selected.allElementsBoundByIndex.map(\.label), before, "swiping the strip changed the selected goal")
        shoot(app, "S2")
    }

    // MARK: - Steps

    /// Opens Add Transaction on Transfer and brings the strip on screen. Drags near the top of
    /// the form, clear of the keyboard iPad may raise on its own.
    @MainActor
    private func openTransfer(_ app: XCUIApplication) {
        let add = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "no Add transaction button")
        add.tap()
        let transfer = app.segmentedControls.buttons["Transfer"]
        XCTAssertTrue(transfer.waitForExistence(timeout: 10), "no Transfer type, so no goals were seeded")
        transfer.tap()
        let goals = strip(app)
        XCTAssertTrue(goals.waitForExistence(timeout: 10), "no goal strip")
        // The form is the only collection view holding a text field (iPad's sidebar and
        // dashboard have none).
        let form = app.collectionViews.containing(.textField, identifier: nil).firstMatch
        for _ in 0..<6 where !goals.isHittable {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        }
        XCTAssertTrue(goals.isHittable, "goal strip never scrolled into view")
    }

    private func strip(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews["goalStrip"]
    }

    @MainActor
    private func assertSelected(_ chip: XCUIElement, _ selected: Bool, _ message: String) {
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "chip missing: \(message)")
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == %@", NSNumber(value: selected)), object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [state], timeout: 5), .completed, message)
    }
}
