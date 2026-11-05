//
//  KeyboardBarScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #56: the keyboard accessory bar (‹ › Done, `keyboardFieldNavigation`) must be there
//  whenever Add Transaction's keyboard is. Not reproducible on current code (2026-11-01):
//  these scenarios guard every path that moves focus while the keyboard is up or the
//  sheet is still opening.
//

import XCTest

final class KeyboardBarScenarioTests: ScenarioTestCase {

    /// The report's screenshot: Add Transaction just opened, Amount auto-focused, no bar.
    /// Opened several times because the reported failure was intermittent. Fewer on iPad: the
    /// form is an inspector there, with no sheet presentation to race, and one regression run
    /// saw the app stop idling after a few inspector open/cancel cycles, costing 60 s per tap.
    @MainActor
    func testS1_barShowsWhenAddOpensFocused() throws {
        let app = launchApp()
        let opens = UIDevice.current.userInterfaceIdiom == .pad ? 3 : 6
        var missing: [Int] = []
        for attempt in 1...opens {
            openAdd(app)
            // A clean install's first iPhone open skips auto-focus (`isFirstEverOpen`).
            if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
                amountField(app).tap()
            }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not appear on open \(attempt)")
            if !bar(app).waitForExistence(timeout: 3) {
                missing.append(attempt)
                shoot(app, "S1-missing-\(attempt)")
            }
            if attempt == opens { break }
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "keyboard stayed after Cancel")
        }
        XCTAssert(missing.isEmpty, "keyboard bar missing on opens \(missing) of \(opens)")
        shoot(app, "S1")
    }

    /// Amount → Name swaps the decimal pad for the full keyboard without dismissing it.
    @MainActor
    func testS2_barSurvivesAmountToName() throws {
        let app = launchApp()
        openAddFocused(app)
        bar(app).tap()
        XCTAssertTrue(waitForFocus(app.textFields["Name (optional)"]), "Name did not take focus")
        XCTAssertTrue(bar(app).waitForExistence(timeout: 3), "keyboard bar missing on Name")
        shoot(app, "S2")
    }

    /// The form clears focus on `.inactive` and restores it on `.active` (#222).
    @MainActor
    func testS3_barSurvivesBackground() throws {
        let app = launchApp()
        openAddFocused(app)
        // Well inside BiometricAuthService.defaultGraceInterval (30 s): no PIN overlay on return.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "keyboard did not come back")
        XCTAssertTrue(bar(app).waitForExistence(timeout: 3), "keyboard bar missing after returning")
        shoot(app, "S3")
    }

    /// Real installs show TipKit tips: the Scan popover on the first open, then the inline
    /// keyboard-bar tip card and its scrim on the auto-focused opens after it.
    @MainActor
    func testS4_barShowsWithTipsOn() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { throw XCTSkip("iPad shows no keyboard-bar tips") }
        let app = launchApp(hideTips: false)
        var missing: [Int] = []
        var sawInlineTip = false
        for attempt in 1...4 {
            openAdd(app)
            if attempt == 1 {
                XCTAssertTrue(app.staticTexts["Scan a receipt"].waitForExistence(timeout: 5), "no Scan popover on the first open: tips are not on")
            }
            // The first open's Scan popover sits over Amount and swallows taps.
            let closeTip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close' OR label CONTAINS[c] 'dismiss tip'")).firstMatch
            if closeTip.waitForExistence(timeout: 2) { closeTip.tap() }
            for _ in 0..<3 where !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
                amountField(app).tap()
            }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not appear on open \(attempt)")
            if !bar(app).waitForExistence(timeout: 3) {
                missing.append(attempt)
                shoot(app, "S4-missing-\(attempt)")
            }
            // The inline card explaining the bar's toggles (`TransactionFormTips`).
            if app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Keep adding", "Make it recurring", "Do the math"])).firstMatch.waitForExistence(timeout: 2) {
                sawInlineTip = true
            }
            if attempt == 4 { break }
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "keyboard stayed after Cancel")
        }
        XCTAssert(missing.isEmpty, "keyboard bar missing on opens \(missing) of 4")
        XCTAssertTrue(sawInlineTip, "no inline tip card showed with the bar: tips were not exercised")
        shoot(app, "S4")
    }

    /// "Keep adding" save: the form resets in place, dropping and then re-taking Amount focus.
    @MainActor
    func testS5_barReturnsAfterKeepAddingSave() throws {
        let app = launchApp()
        openAddFocused(app)
        amountField(app).typeText("5")
        app.buttons["Keep adding"].tap()
        let chip = app.scrollViews["categoryStrip"].staticTexts.firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no category chip")
        chip.tap()
        let save = app.buttons["Add Transaction"]
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.isEnabled, "save not enabled")
        save.tap()
        // The form resets in place: nothing to save until the next amount.
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [reset], timeout: 5), .completed, "form did not reset after save")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not come back after save")
        XCTAssertTrue(bar(app).waitForExistence(timeout: 3), "keyboard bar missing after Keep adding save")
        shoot(app, "S5")
    }

    /// #347: iPhone's bar shows only icons, but VoiceOver still needs each button's name.
    @MainActor
    func testS6_barButtonsKeepTheirNames() throws {
        let app = launchApp()
        openAddFocused(app)
        for name in ["Keep adding", "Repeat", "Math operation"] {
            XCTAssertTrue(app.buttons[name].exists, "no button named \(name) in the keyboard bar")
        }
        shoot(app, "S6")
    }

    // MARK: - Steps

    @MainActor
    private func openAdd(_ app: XCUIApplication) {
        let add = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "no Add transaction button")
        add.tap()
        XCTAssertTrue(amountField(app).waitForExistence(timeout: 10), "no amount field")
    }

    @MainActor
    private func openAddFocused(_ app: XCUIApplication) {
        openAdd(app)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            amountField(app).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not appear for Amount")
        XCTAssertTrue(bar(app).waitForExistence(timeout: 3), "keyboard bar missing on Amount")
    }

    /// CurrencyAmountField: placeholder "0", no accessibility label of its own.
    private func amountField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == '0'")).firstMatch
    }

    /// "Next field" is the bar's own chevron; nothing else on these screens has that label.
    private func bar(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Next field"]
    }

    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: 5) == .completed
    }
}
