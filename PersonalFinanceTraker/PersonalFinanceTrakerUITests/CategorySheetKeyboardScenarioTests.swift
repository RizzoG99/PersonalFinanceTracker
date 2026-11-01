//
//  CategorySheetKeyboardScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #259: opening the full category list ("More") from Add Transaction must not leave the
//  keyboard over the sheet. Scenarios S1–S4 are the acceptance contract in the issue.
//

import XCTest

final class CategorySheetKeyboardScenarioTests: ScenarioTestCase {

    @MainActor
    func testS1_moreHidesKeyboard() throws {
        let app = launchApp()
        openCategorySheetFromFocusedAmount(app)
        assertKeyboardGone(app, "keyboard still over the category sheet")
        // Amount stays focused underneath unless the form clears it, and the system restores
        // that focus: on the simulator only after the sheet closes (S2), on a device while it
        // is still up (the reported bug). Hold the check for a moment to catch the latter.
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "keyboard came back over the category sheet")
        shoot(app, "S1")
        try auditAccessibility(app, "S1", screens: "CategoryPicker")
    }

    @MainActor
    func testS2_pickingCategoryKeepsKeyboardHidden() throws {
        let app = launchApp()
        let inline = openCategorySheetFromFocusedAmount(app)

        // A category only the full list has: picking it must add it to the inline strip
        // (`inlineCategories` appends an out-of-top-5 selection; the chip itself exposes no
        // selected state, see #270).
        let grid = app.scrollViews["categoryPickerGrid"]
        let picked = try XCTUnwrap(
            grid.staticTexts.allElementsBoundByIndex.first { !inline.contains($0.label) && $0.isHittable },
            "no category outside the inline strip is visible in the sheet"
        )
        let name = picked.label
        picked.tap()

        XCTAssertTrue(app.navigationBars["Category"].waitForNonExistence(timeout: 5), "sheet did not close")
        XCTAssertTrue(strip(app).staticTexts[name].waitForExistence(timeout: 5), "'\(name)' is not in the strip after picking it")
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2), "keyboard came back after the sheet closed")
        shoot(app, "S2")
        // iPad shows the form as an inspector beside Home.
        try auditAccessibility(app, "S2", screens: "AddTransaction", "Home")
    }

    @MainActor
    func testS3_searchStillShowsKeyboard() throws {
        let app = launchApp()
        openCategorySheetFromFocusedAmount(app)
        // Otherwise Amount's leftover keyboard would satisfy the check below.
        assertKeyboardGone(app, "keyboard still over the category sheet")
        let search = app.searchFields["Search categories"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search field in the category sheet")
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "search field did not bring up the keyboard")
        search.typeText("Gro")
        // typeText can return before the field's value catches up on a loaded machine. Not
        // `search` itself: once it holds text it no longer always matches by its placeholder
        // label (seen at AX-XXXL), and the sheet has only one search field.
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Gro'"), object: app.searchFields.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [typed], timeout: 5), .completed, "typing did not reach the search field")
        shoot(app, "S3")
    }

    /// Regression for #222: focus on Amount survives a trip to the background.
    @MainActor
    func testS4_amountFocusSurvivesBackground() throws {
        let app = launchApp()
        let amount = openAddWithAmountFocused(app)

        // Well inside BiometricAuthService.defaultGraceInterval (30 s): no PIN overlay on return.
        XCUIDevice.shared.press(.home)
        app.activate()

        // Returning from the background restores focus after the resume animation; on a
        // loaded machine that has taken over 5 s.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "keyboard did not come back")
        XCTAssertEqual(amount.value(forKey: "hasKeyboardFocus") as? Bool, true, "Amount lost focus")
        shoot(app, "S4")
    }

    // MARK: - Steps

    /// Opens Add Transaction and focuses Amount by tapping it: a clean install's first iPhone
    /// open deliberately skips auto-focus (`TransactionFormView.isFirstEverOpen`).
    @MainActor
    @discardableResult
    private func openAddWithAmountFocused(_ app: XCUIApplication) -> XCUIElement {
        let add = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "no Add transaction button")
        add.tap()
        // CurrencyAmountField: placeholder "0", no accessibility label of its own.
        let amount = app.textFields.matching(NSPredicate(format: "placeholderValue == '0'")).firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "no amount field")
        amount.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not appear for Amount")
        return amount
    }

    /// From a focused Amount, scrolls to the category strip and taps "More", keyboard still up.
    /// Returns the labels the inline strip showed before the sheet opened.
    @MainActor
    @discardableResult
    private func openCategorySheetFromFocusedAmount(_ app: XCUIApplication) -> Set<String> {
        openAddWithAmountFocused(app)
        // The form is the only collection view holding a text field (iPad's sidebar and
        // dashboard have none).
        let form = app.collectionViews.containing(.textField, identifier: nil).firstMatch
        let categories = strip(app)

        // Drag inside the top of the form, clear of the keyboard, until the strip is reachable.
        for _ in 0..<6 where !categories.isHittable {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        }
        XCTAssertTrue(categories.isHittable, "category strip never scrolled into view")

        let more = categories.buttons.matching(NSPredicate(format: "label CONTAINS 'More'")).firstMatch
        for _ in 0..<4 where !more.isHittable {
            categories.swipeLeft()
        }
        XCTAssertTrue(more.isHittable, "More chip not reachable")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard went away before tapping More — precondition broken")
        let inline = Set(categories.staticTexts.allElementsBoundByIndex.map(\.label))

        more.tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5), "category sheet did not open")
        return inline
    }

    private func strip(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews["categoryStrip"]
    }

    @MainActor
    private func assertKeyboardGone(_ app: XCUIApplication, _ message: String) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), message)
    }
}
