//
//  CategoryChipAccessibilityScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #270: category chips are buttons and expose their selected state, in the Add Transaction
//  strip, the "More" sheet and Activity's bulk picker. Scenarios S1–S4 are the contract in
//  the issue.
//

import XCTest

final class CategoryChipAccessibilityScenarioTests: ScenarioTestCase {

    @MainActor
    func testS1_stripChipsAreSelectableButtons() throws {
        let app = launchApp()
        openAdd(app)
        let (first, second) = try firstTwoChips(app)

        first.tap()
        assertSelected(first, true, "first chip not selected after tapping it")
        second.tap()
        assertSelected(second, true, "second chip not selected after tapping it")
        assertSelected(first, false, "first chip still selected after picking another")
        shoot(app, "S1")
        try auditAccessibility(app, "S1", screens: "AddTransaction", "Home")
    }

    @MainActor
    func testS2_moreSheetShowsAndChangesSelection() throws {
        let app = launchApp()
        openAdd(app)
        let (first, _) = try firstTwoChips(app)
        let selectedName = first.label
        first.tap()
        assertSelected(first, true, "chip not selected before opening More")
        let inline = Set(strip(app).buttons.allElementsBoundByIndex.map(\.label))

        let more = moreChip(app)
        for _ in 0..<4 where !more.isHittable {
            strip(app).swipeLeft()
        }
        more.tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5), "category sheet did not open")

        let grid = app.scrollViews["categoryPickerGrid"]
        assertSelected(grid.buttons[selectedName], true, "current category not selected in the sheet")
        shoot(app, "S2")
        try auditAccessibility(app, "S2", screens: "CategoryPicker", "AddTransaction", "Home")

        let picked = try XCTUnwrap(
            grid.buttons.allElementsBoundByIndex.first { !inline.contains($0.label) && $0.isHittable },
            "no category outside the inline strip is visible in the sheet"
        )
        let pickedName = picked.label
        picked.tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForNonExistence(timeout: 5), "sheet did not close")
        assertSelected(strip(app).buttons[pickedName], true, "picked category not selected in the strip")
        assertSelected(strip(app).buttons[selectedName], false, "old category still selected in the strip")
    }

    @MainActor
    func testS3_bulkPickerChipsApplyCategory() throws {
        let app = launchApp()
        let onActivity = openCategoryPickerFromActivity(app)

        let grid = app.scrollViews["categoryPickerGrid"]
        XCTAssertTrue(grid.buttons.firstMatch.waitForExistence(timeout: 5), "no category button in the bulk picker")
        // A category Activity doesn't show yet, so seeing it afterwards proves it was applied.
        let picked = try XCTUnwrap(
            grid.buttons.allElementsBoundByIndex.first { !onActivity.contains($0.label) && $0.isHittable },
            "every visible category is already on the Activity screen"
        )
        let name = picked.label
        shoot(app, "S3")
        picked.tap()

        XCTAssertTrue(app.navigationBars["Category"].waitForNonExistence(timeout: 5), "sheet did not close")
        let applied = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(applied.waitForExistence(timeout: 5), "'\(name)' was not applied to the transaction")
    }

    @MainActor
    func testS4_swipingStripSelectsNothing() throws {
        let app = launchApp()
        openAdd(app)

        // At least one swipe, even where More already fits on screen.
        let more = moreChip(app)
        strip(app).swipeLeft()
        for _ in 0..<3 where !more.isHittable {
            strip(app).swipeLeft()
        }
        XCTAssertTrue(more.isHittable, "strip did not scroll to More")
        let selected = strip(app).buttons.matching(NSPredicate(format: "selected == true"))
        XCTAssertEqual(selected.count, 0, "swiping the strip selected a chip")
        shoot(app, "S4")
    }

    // MARK: - Steps

    /// Opens Add Transaction and brings the strip on screen. Drags near the top of the form,
    /// clear of the keyboard iPad may raise on its own.
    @MainActor
    private func openAdd(_ app: XCUIApplication) {
        let add = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "no Add transaction button")
        add.tap()
        let categories = strip(app)
        XCTAssertTrue(categories.waitForExistence(timeout: 10), "no category strip")
        // The form is the only collection view holding a text field (iPad's sidebar and
        // dashboard have none).
        let form = app.collectionViews.containing(.textField, identifier: nil).firstMatch
        for _ in 0..<6 where !categories.isHittable {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        }
        XCTAssertTrue(categories.isHittable, "category strip never scrolled into view")
    }

    /// The strip's first two buttons: More comes last, after every category chip.
    @MainActor
    private func firstTwoChips(_ app: XCUIApplication) throws -> (XCUIElement, XCUIElement) {
        let labels = strip(app).buttons.allElementsBoundByIndex.map(\.label).filter { $0 != "More" }
        let first = try XCTUnwrap(labels.first, "no category button in the strip")
        let second = try XCTUnwrap(labels.dropFirst().first, "only one category button in the strip")
        return (strip(app).buttons[first], strip(app).buttons[second])
    }

    /// Selects one transaction and opens the bulk picker. iPhone: a long-press enters selection
    /// mode and selects the row, then the bar's Category. iPad: a tap opens the row in the
    /// inspector, so the ledger's context menu instead. Returns the Activity screen's
    /// accessibility tree as text, read before the sheet covers it.
    @MainActor
    private func openCategoryPickerFromActivity(_ app: XCUIApplication) -> String {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad {
            let sidebar = app.collectionViews["Sidebar"]
            sidebar.staticTexts["Activity"].firstMatch.tap()
            // While the portrait overlay slides away, a press on a row lands on the sidebar.
            // Not asserted: a wide layout keeps the sidebar open.
            _ = sidebar.waitForNonExistence(timeout: 5)
        } else {
            app.tabBars.buttons["Activity"].tap()
        }
        let row = isPad
            ? app.staticTexts["Morning coffee"].firstMatch
            : app.buttons.matching(NSPredicate(format: "label CONTAINS 'Morning coffee'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no transaction row in Activity")
        let onActivity = app.debugDescription
        row.press(forDuration: 1)
        // iPhone: enabled, because Activity's Category filter has the same name and stays
        // disabled until a type is chosen.
        let category = isPad
            ? app.buttons["Set Category…"].firstMatch
            : app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Category' AND enabled == true")).firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5), "no bulk Category action")
        category.tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5), "bulk picker did not open")
        return onActivity
    }

    private func strip(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews["categoryStrip"]
    }

    private func moreChip(_ app: XCUIApplication) -> XCUIElement {
        strip(app).buttons.matching(NSPredicate(format: "label CONTAINS 'More'")).firstMatch
    }

    @MainActor
    private func assertSelected(_ chip: XCUIElement, _ selected: Bool, _ message: String) {
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "chip missing: \(message)")
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == %@", NSNumber(value: selected)), object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [state], timeout: 5), .completed, message)
    }
}
