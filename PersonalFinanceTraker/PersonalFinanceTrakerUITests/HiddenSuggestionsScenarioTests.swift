//
//  HiddenSuggestionsScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #214: a fixed-expense suggestion answered "Not fixed" can be seen and brought back from
//  Recurring. Scenarios S1–S6 are the acceptance contract in the issue. `-seedFixedExpenseCards`
//  gives each test its suggestions (plus two missed rules unless `-fixedExpenseSuggestionsOnly`).
//

import XCTest

final class HiddenSuggestionsScenarioTests: ScenarioTestCase {

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private let seed = ["-seedFixedExpenseCards"]
    private let suggestionsOnly = ["-seedFixedExpenseCards", "-fixedExpenseSuggestionsOnly"]

    @MainActor
    func testS1_dismissedSuggestionIsListed() throws {
        let app = launchApp(seed)
        let title = dismissFirstSuggestion(app)
        openRecurring(app)
        // The List branch: rules exist. Lazy and below the cards at large sizes, so scroll first.
        scrollUntilHittable(app, ruleRow(app, "Palestra"))

        let row = hiddenRow(app)
        scrollUntilHittable(app, row)
        XCTAssertTrue(row.label.contains("1"), "the row doesn't count one hidden suggestion: \(row.label)")
        // iPad: with the form sheet up the audit reports unattributed "Potentially inaccessible
        // text" findings (#269), so the pane is audited here and the sheet, the same view, on iPhone.
        if isPad { try auditAccessibility(app, "S1", screens: "Recurring") }
        row.tap()

        XCTAssertTrue(app.navigationBars["Hidden suggestions"].waitForExistence(timeout: 10), "the hidden list didn't open")
        let listed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", title, "Monthly", "€"))
            .firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 5), "\(title) isn't listed with its cadence and amount")
        XCTAssertTrue(app.buttons["Show \(title) again"].exists, "no Show again for \(title)")
        shoot(app, "S1")
        if !isPad { try auditAccessibility(app, "S1", screens: "Recurring", "HiddenSuggestions") }
    }

    @MainActor
    func testS2_showAgainBringsTheCardBack() throws {
        let app = launchApp(suggestionsOnly)
        let title = dismissFirstSuggestion(app)
        XCTAssertFalse(card(app, title).waitForExistence(timeout: 2), "the dismissed card is still there")

        openRecurring(app)
        let row = hiddenRow(app)
        scrollUntilHittable(app, row)
        row.tap()
        let showAgain = app.buttons["Show \(title) again"]
        XCTAssertTrue(showAgain.waitForExistence(timeout: 10), "no Show again for \(title)")
        showAgain.tap()

        XCTAssertTrue(app.navigationBars["Hidden suggestions"].waitForNonExistence(timeout: 10), "the empty hidden list stayed open")
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "the row stayed with nothing hidden")
        if !isPad { app.buttons["Close"].tap() }
        let restored = card(app, title)
        // Plan stays scrolled down to "See all" (AX sizes), and the card is at the top.
        for _ in 0..<6 where !(restored.waitForExistence(timeout: 2) && restored.isHittable) {
            app.swipeDown()
        }
        XCTAssertTrue(restored.isHittable, "\(title)'s card didn't come back")
        shoot(app, "S2")
        try auditAccessibility(app, "S2", screens: isPad ? "Recurring" : "Plan")
    }

    @MainActor
    func testS3_nothingHiddenShowsNoRow() throws {
        let app = launchApp(seed)
        openRecurring(app)
        scrollUntilHittable(app, ruleRow(app, "Palestra"))
        for _ in 0..<3 { app.swipeUp() }

        XCTAssertFalse(hiddenRow(app).waitForExistence(timeout: 2), "a hidden-suggestions row with nothing hidden")
        shoot(app, "S3")
        try auditAccessibility(app, "S3", screens: "Recurring")
    }

    @MainActor
    func testS4_rowShowsUnderTheEmptyState() throws {
        let app = launchApp(suggestionsOnly)
        _ = dismissFirstSuggestion(app)
        openRecurring(app)

        XCTAssertTrue(app.staticTexts["No recurring transactions yet"].waitForExistence(timeout: 10), "not on the empty state")
        let row = hiddenRow(app)
        scrollUntilHittable(app, row)
        shoot(app, "S4")
        try auditAccessibility(app, "S4", screens: "Recurring")
    }

    @MainActor
    func testS5_hideAmountsBlursTheList() throws {
        let app = launchApp(seed)
        let title = dismissFirstSuggestion(app)
        if isPad {
            app.collectionViews["Sidebar"].staticTexts["Home"].firstMatch.tap()
        } else {
            app.tabBars.buttons["Home"].tap()
        }
        let hide = app.buttons["Hide amounts"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 10), "no Hide amounts on Home")
        hide.tap()

        openRecurring(app)
        let row = hiddenRow(app)
        scrollUntilHittable(app, row)
        row.tap()

        XCTAssertTrue(app.navigationBars["Hidden suggestions"].waitForExistence(timeout: 10), "the hidden list didn't open")
        XCTAssertTrue(element(app, containing: title, "Amount hidden").waitForExistence(timeout: 5), "\(title)'s amount isn't hidden")
        shoot(app, "S5")
    }

    @MainActor
    func testS6_undoLeavesNothingHidden() throws {
        let app = launchApp(seed)
        cardsHost(app)
        let notFixed = revealNotFixed(app)
        notFixed.tap()
        let title = toastTitle(app)
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo in the toast")
        undo.tap()

        XCTAssertTrue(card(app, title).waitForExistence(timeout: 10), "Undo didn't bring \(title) back")
        closeReviewSheet(app)
        openRecurring(app)
        for _ in 0..<3 { app.swipeUp() }
        // Longer than the 5 s toast: an undone answer must never be written late.
        XCTAssertFalse(hiddenRow(app).waitForExistence(timeout: 6), "the undone suggestion was hidden anyway")
        shoot(app, "S6")
    }

    /// Critique-added: with no rules, budgets or goals, Plan is the welcome state and has no
    /// "See all" — the hidden list must still be reachable. iPhone only: iPad has no Plan tab.
    @MainActor
    func testS7_planWelcomeReachesHiddenList() throws {
        try XCTSkipIf(isPad, "iPad has no Plan tab")
        let app = launchApp(suggestionsOnly + ["-clearBudgets"])
        let title = dismissFirstSuggestion(app)
        XCTAssertTrue(app.staticTexts["Plan what's ahead"].waitForExistence(timeout: 10), "Plan isn't on its welcome state")

        let row = hiddenRow(app)
        scrollUntilHittable(app, row)
        row.tap()
        XCTAssertTrue(app.buttons["Show \(title) again"].waitForExistence(timeout: 10), "no Show again for \(title)")
        shoot(app, "S7")
        try auditAccessibility(app, "S7", screens: "Plan", "HiddenSuggestions")
    }

    // MARK: - Steps

    /// iPhone: the cards live on Plan. iPad: on the Recurring pane.
    @MainActor
    private func cardsHost(_ app: XCUIApplication) {
        if isPad {
            app.collectionViews["Sidebar"].staticTexts["Recurring"].firstMatch.tap()
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar never appeared")
            app.tabBars.buttons["Plan"].tap()
        }
    }

    /// The first "Not fixed": inline, or in "Review N more" when the missed cards fill the inline slots.
    @MainActor
    private func revealNotFixed(_ app: XCUIApplication) -> XCUIElement {
        let notFixed = app.buttons["Not fixed"].firstMatch
        if !notFixed.waitForExistence(timeout: 5) {
            let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review ")).firstMatch
            scrollUntilHittable(app, review)
            review.tap()
            XCTAssertTrue(notFixed.waitForExistence(timeout: 10), "no Not fixed in the review sheet")
        }
        scrollUntilHittable(app, notFixed)
        return notFixed
    }

    /// "Won't suggest <title> again" → <title>.
    @MainActor
    private func toastTitle(_ app: XCUIApplication) -> String {
        let toast = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Won't suggest ")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "no undo toast")
        return String(toast.label.dropFirst("Won't suggest ".count).dropLast(" again".count))
    }

    /// Answers "Not fixed" to the first suggestion and waits out the toast, which writes it.
    @MainActor
    private func dismissFirstSuggestion(_ app: XCUIApplication) -> String {
        cardsHost(app)
        revealNotFixed(app).tap()
        let title = toastTitle(app)
        let toast = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Won't suggest ")).firstMatch
        XCTAssertTrue(toast.waitForNonExistence(timeout: 15), "the undo toast never went")
        closeReviewSheet(app)
        return title
    }

    @MainActor
    private func closeReviewSheet(_ app: XCUIApplication) {
        let bar = app.navigationBars["Check your fixed expenses"]
        guard bar.exists else { return }
        bar.buttons["Done"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10), "the review sheet didn't close")
    }

    @MainActor
    private func openRecurring(_ app: XCUIApplication) {
        if isPad {
            app.collectionViews["Sidebar"].staticTexts["Recurring"].firstMatch.tap()
        } else {
            app.tabBars.buttons["Plan"].tap()
            let seeAll = app.buttons["See all"].firstMatch
            scrollUntilHittable(app, seeAll)
            seeAll.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "Recurring didn't open")
        }
    }

    private func hiddenRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["hiddenSuggestionsRow"]
    }

    /// A rule row's `Button` combines its texts, so the label holds the title among other things.
    private func ruleRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// A suggestion card's combined row: title, "Monthly · seen N times", amount.
    private func card(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        element(app, containing: title, "seen")
    }

    private func element(_ app: XCUIApplication, containing first: String, _ second: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", first, second))
            .firstMatch
    }

    /// At the largest text sizes cards and stat tiles fill the first screen, and lists are lazy.
    @MainActor
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 2) && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("\(element) never became hittable")
    }
}
