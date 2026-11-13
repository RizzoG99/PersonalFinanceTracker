//
//  ScenarioTestCase.swift
//  PersonalFinanceTrakerUITests
//
//  Base class for acceptance-scenario tests: one test per scenario (S1..Sn) from the
//  GitHub issue, run on iPhone and iPad. Assertions are the pass/fail gate; the
//  screenshots from `shoot` are kept for agent review, never compared pixel by pixel.
//
//  XCTest, not Swift Testing: XCUITest only runs on XCTest. The "Swift Testing, not
//  XCTest" rule in CLAUDE.md covers unit tests only.
//

import XCTest

class ScenarioTestCase: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Same opt-in as ScreenshotTests: the pass setup (appearance, text size, clean
        // install) lives in the script, so a plain `scripts/xcb test` or CI run skips these.
        guard ProcessInfo.processInfo.environment["SCENARIO_VARIANT"] != nil else {
            throw XCTSkip("Run via scripts/xcb scenarios")
        }
        // The simulator keeps whatever orientation it was last left in (runs have come up
        // in landscape), and scenarios are specified in portrait.
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// A failed scenario keeps a picture of where it stopped (`<test>-failure-…`), since
    /// `scripts/xcb scenarios` turns off xcodebuild's own diagnostics collection.
    override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0 {
            // XCTest runs tearDown on the main thread; XCUIScreen is main-actor isolated.
            MainActor.assumeIsolated {
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "\(name.split(separator: " ").last?.dropLast() ?? "test")-failure-\(idiom)-\(variant)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        super.tearDown()
    }

    /// App on Home with sample data. `-skipOnboarding` (DEBUG) resets every setting and
    /// replaces tapping through PIN setup, name entry, the restore prompt and What's New;
    /// `-seedSampleData` replaces transactions and categories. Goals, recurring rules and
    /// trips a test creates survive until the pass's next reinstall: create what you need,
    /// assume nothing about what is already there. `hideTips: false` resets TipKit instead,
    /// for scenarios about what a real first-run user sees.
    @MainActor
    func launchApp(_ extraArguments: [String] = [], hideTips: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments(hideTips: hideTips) + extraArguments
        app.launch()
        // The sidebar holds the navigation and "Add transaction" every scenario starts from. It
        // used to open collapsed now and then, with the whole split at 448 pt (#358); tapping
        // "Show Sidebar" did not fix that, so a collapsed sidebar now fails instead.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.collectionViews["Sidebar"].waitForExistence(timeout: 10), "iPad sidebar collapsed at launch: the narrow layout of #358 is back")
        }
        return app
    }

    /// `launchApp`'s arguments, for a test that launches the app itself.
    static func launchArguments(hideTips: Bool) -> [String] {
        [
            "-skipOnboarding",
            "-seedSampleData",
            hideTips ? "-hideTips" : "-resetTips",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_IE",
        ]
    }

    /// Attaches a screenshot named `<scenario>-<topic>-<iphone|ipad>-<variant>` (variant:
    /// light, dark, light-axxxl) and keeps it in the result bundle even when the test passes.
    @MainActor
    func shoot(_ app: XCUIApplication, _ scenario: String) {
        // Whole screen, not the app window: the keyboard and the lock overlay are
        // separate windows, and they are often what the scenario is about.
        let attachment = XCTAttachment(screenshot: settledScreenshot())
        attachment.name = "\(scenario)-\(topic)-\(idiom)-\(variant)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls by the same distance on every run, so screenshots land on the same offset:
    /// `swipeUp()` travels a different distance each time. Holding before the lift leaves no
    /// momentum. It covers less ground than a swipe, so loops around it need more turns.
    @MainActor
    func scrollUp(_ scrollView: XCUIElement) {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// The screen once two captures in a row match, so scroll momentum or a fading sidebar
    /// doesn't reach the picture or the audit that follows it. A blinking cursor can keep it
    /// from settling; it then returns the latest capture after the time limit.
    @MainActor
    private func settledScreenshot() -> XCUIScreenshot {
        var shot = XCUIScreen.main.screenshot()
        let deadline = Date.now.addingTimeInterval(3)
        while Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let next = XCUIScreen.main.screenshot()
            if next.pngRepresentation == shot.pngRepresentation { return next }
            shot = next
        }
        return shot
    }

    /// Pre-existing audit findings, each tracked on GitHub: they don't fail a scenario,
    /// anything else does. Matched on the screens passed to `auditAccessibility` ("*" for
    /// chrome on every screen, like the iPad sidebar), the audit description and one of the
    /// element labels ("?" when the audit names no element; "*" stands for the varying part of
    /// a label holding dates or amounts, like "€* / €*"; "value=…" matches an unlabeled element by
    /// what it holds). Keep labels exact: a broad pattern would hide a new finding on the same
    /// screen. Delete an entry when its issue is fixed.
    static let knownAccessibilityIssues: [(screen: String, description: String, labels: [String], issue: Int)] = [
        ("*", "Text clipped", ["Home", "Settings"], 219),
        ("*", "Dynamic Type font sizes are partially unsupported", ["Settings", "New"], 219),

        ("Home", "Text clipped", ["until *"], 268),
        ("Home", "Text clipped", ["Coffee & Drinks", "Streaming Services", "Financial Pulse", "Today's check-in is complete", "€* / €*"], 357),
        // Financial Pulse quick-log buttons with `-seedPendingCheckIn`'s two habits (#215's S1).
        ("Home", "Text clipped", ["Log Morning coffee", "Log Bus ticket", "-€3.50", "-€2.00"], 357),
        ("Home", "Potentially inaccessible text", ["?"], 269),
        // iPad Recent Transactions rows (SampleData names, their categories and amounts).
        ("Home", "Dynamic Type font sizes are partially unsupported", [
            "Recent Transactions", "-€*", "+€*",
            "Morning coffee", "Lunch at bistro", "Monthly salary", "Weekly groceries", "Gas station", "Netflix subscription",
            "Coffee & Drinks", "Restaurants", "Salary", "Groceries", "Streaming Services", "Gas",
        ], 275),
        // iPad near-limit budget bars: category name and "€spent / €budget" (#342's scenarios).
        ("Home", "Dynamic Type font sizes are partially unsupported", ["Clothing", "Streaming Services", "€* / €*"], 345),

        // The name field: it has no label, and `-skipOnboarding` fills in "Alex".
        ("Settings", "Text clipped", ["value=Alex"], 353),
        ("Settings", "Dynamic Type font sizes are partially unsupported", ["DATA"], 354),
        ("Settings", "Dynamic Type font sizes are unsupported", ["DISCOVER"], 354),
        // The backup rows under "Back Up Now"; "?" are unlabeled elements beside them (iPhone).
        ("Settings", "Dynamic Type font sizes are partially unsupported", ["Restore from Backup", "Delete All Data", "?"], 393),
        ("Settings", "Text clipped", ["Restore from Backup", "Delete All Data", "?"], 393),
        ("Settings", "Dynamic Type font sizes are unsupported", ["?"], 393),
        // iOS 26.5 only (the cloud runner's simulator); iOS 27.0 reports neither.
        ("Settings", "Dynamic Type font sizes are partially unsupported", ["Export Transactions", "CSV or Excel"], 412),
        ("Settings", "Text clipped", ["Export Transactions", "DISCOVER"], 412),

        // Unattributed, and only on some runs (iPad dark, #215's S2), like Home's.
        ("SiriGuide", "Potentially inaccessible text", ["?"], 269),
        // Siri & Widgets guide phrase rows and their Copy button.
        ("SiriGuide", "Text clipped", [
            "Exact Siri phrase: Add a transaction in Personal Finance", "Exact Siri phrase: Log an expense in Personal Finance",
        ], 392),
        ("SiriGuide", "Dynamic Type font sizes are partially unsupported", [
            "Exact Siri phrase: Add a transaction in Personal Finance", "Exact Siri phrase: Log an expense in Personal Finance",
            "Copy", "Copied",
        ], 392),

        // Category chips in the inline strip and the More chip.
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", defaultCategoryNames + ["More"], 271),
        ("AddTransaction", "Text clipped", defaultCategoryNames, 271),
        // Goal chips, with `-seedGoalProjections`' first goals on screen.
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", ["Japan trip", "New laptop", "Emergency fund"], 363),
        ("AddTransaction", "Text clipped", ["Japan trip", "New laptop", "Emergency fund"], 363),
        // The amount field and its currency symbol.
        ("AddTransaction", "Element has no description", [""], 272),
        ("AddTransaction", "Dynamic Type font sizes are unsupported", ["", "€"], 272),
        ("AddTransaction", "Text clipped", [""], 272),
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", ["Cancel"], 273),
        ("AddTransaction", "Text clipped", ["New Transaction"], 273),
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", ["Group a trip's expenses*"], 274),

        ("Recurring", "Dynamic Type font sizes are partially unsupported", ["Close"], 273),
        ("Recurring", "Label not human-readable", ["-€*"], 349),

        // Fixed-expense suggestion cards: Plan on iPhone, Recurring on iPad.
        ("Plan", "Dynamic Type font sizes are partially unsupported", ["Not fixed", "Plan for it"], 378),
        ("Recurring", "Dynamic Type font sizes are partially unsupported", ["Not fixed", "Plan for it"], 378),
        ("Plan", "Text clipped", ["About -€*, varies"], 378),
        ("Recurring", "Text clipped", ["About -€*, varies"], 378),
        // Plan's Coming up header and its no-rules empty state.
        ("Plan", "Hit area is too small", ["See all"], 379),
        ("Plan", "Dynamic Type font sizes are partially unsupported", [
            "Coming up", "Next 14 days", "See all", "No recurring payments", "Add rent, subscriptions or bills to see them coming.",
        ], 379),

        // iPad: the sections below the fixed-expense cards — stat cards (`-seedFixedExpenseCards`'
        // two rules) and the hidden-suggestions row with one hidden.
        ("Recurring", "Dynamic Type font sizes are partially unsupported", [
            "Active", "2", "Monthly spend", "-€235.00", "Hidden suggestions", "1",
        ], 381),

        ("HiddenSuggestions", "Dynamic Type font sizes are partially unsupported", ["Done"], 273),

        ("CategoryPicker", "Dynamic Type font sizes are partially unsupported", defaultCategoryNames, 271),
        ("CategoryPicker", "Text clipped", defaultCategoryNames, 271),
        ("CategoryPicker", "Dynamic Type font sizes are partially unsupported", ["Cancel"], 273),
        ("CategoryPicker", "Text clipped", ["Cancel"], 273),
        ("CategoryPicker", "Potentially inaccessible text", ["?"], 269),
        ("CategoryPicker", "Potentially inaccessible element", ["?"], 269),
    ]

    /// The chip labels a scenario can meet. Mirrors the keys of `DefaultCategoryRefresh`
    /// (the UI test target can't import the app); exact names, so a new finding on any
    /// other element of those screens still fails.
    static let defaultCategoryNames = [
        "Salary", "Gift", "Investment", "Freelance", "Rental Income", "Bonus", "Prize", "Refund", "Other",
        "Groceries", "Restaurants", "Coffee & Drinks", "Takeout", "Gas", "Car Maintenance", "Public Transport",
        "Taxi & Rideshare", "Rent/Mortgage", "Utilities", "Phone Bill", "Internet", "Streaming Services", "Clothing",
        "Shopping", "Electronics", "Books & Education", "Healthcare", "Pharmacy", "Gym & Fitness", "Personal Care",
        "Entertainment", "Music", "Hobbies", "Travel", "Education", "Pets", "Banking Fees",
    ]

    /// Objective accessibility gate for what is on display (hit regions, clipped and
    /// Dynamic Type text, labels). Call it on every screen a scenario changes. Fails once
    /// with every new finding rather than stopping at the first.
    ///
    /// The audit covers the whole app, not one view: list every screen that can be visible
    /// at that moment. On iPad the Add/Edit form is an inspector beside Home, so pass both.
    ///
    /// Contrast is reported, not enforced: on the glass cards its findings change from
    /// run to run (and SampleData's dates change the rows on screen), so they go to a
    /// `<scenario>-contrast-…txt` report for the screenshot review instead. See #224.
    ///
    /// The `Scenarios` workflow sets `SCENARIO_DYNAMIC_TYPE_REPORT_ONLY`, which does the same
    /// for new Dynamic Type findings (`<scenario>-dynamictype-…txt`): on the hosted runner that
    /// audit now and then reports every element on a screen, on a different test each run.
    /// Locally they still fail the scenario.
    @MainActor
    func auditAccessibility(_ app: XCUIApplication, _ scenario: String, screens: String...) throws {
        let dynamicTypeReportOnly = ProcessInfo.processInfo.environment["SCENARIO_DYNAMIC_TYPE_REPORT_ONLY"] != nil
        var failures: [String] = []
        var reports: [String: [String]] = [:]
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? "?"
            let line = "\(issue.compactDescription) — '\(label)'"
            if issue.auditType == .contrast {
                reports["contrast", default: []].append(line)
            } else if !Self.isKnown(screens, issue.compactDescription, label),
                      !Self.isKnown(screens, issue.compactDescription, "value=\(issue.element?.value as? String ?? "")") {
                if issue.auditType == .dynamicType, dynamicTypeReportOnly {
                    reports["dynamictype", default: []].append(line)
                } else {
                    failures.append(line)
                }
            }
            return true
        }
        for (kind, lines) in reports {
            let report = XCTAttachment(string: lines.joined(separator: "\n"))
            report.name = "\(scenario)-\(topic)-\(kind)-\(idiom)-\(variant).txt"
            report.lifetime = .keepAlways
            add(report)
        }
        XCTAssert(failures.isEmpty, "New accessibility issues in \(scenario) on \(screens.joined(separator: "+")):\n" + failures.joined(separator: "\n"))
    }

    private static func isKnown(_ screens: [String], _ description: String, _ label: String) -> Bool {
        knownAccessibilityIssues.contains { known in
            (known.screen == "*" || screens.contains(known.screen))
                && known.description == description
                && known.labels.contains { pattern in
                    pattern.contains("*") ? NSPredicate(format: "SELF LIKE %@", pattern).evaluate(with: label) : label == pattern
                }
        }
    }

    /// The class name minus "ScenarioTests": every task numbers its scenarios from S1, and
    /// the regression run collects all of them in one folder.
    private var topic: String {
        String(describing: type(of: self)).replacingOccurrences(of: "ScenarioTests", with: "")
    }

    private var idiom: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    /// Set by `scripts/xcb scenarios` per pass; labels the attachments.
    private var variant: String {
        ProcessInfo.processInfo.environment["SCENARIO_VARIANT"] ?? ""
    }
}
