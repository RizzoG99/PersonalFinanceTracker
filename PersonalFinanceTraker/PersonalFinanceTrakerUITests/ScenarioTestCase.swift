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

    /// Clean app on Home with sample data: `-skipOnboarding` (DEBUG) replaces tapping
    /// through PIN setup, name entry, the restore prompt and What's New.
    @MainActor
    func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skipOnboarding",
            "-seedSampleData",
            "-hideTips",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_IE",
        ] + extraArguments
        app.launch()
        return app
    }

    /// Attaches a screenshot named `<scenario>-<iphone|ipad>-<variant>` (variant: light,
    /// dark, light-axxxl) and keeps it in the result bundle even when the test passes.
    @MainActor
    func shoot(_ app: XCUIApplication, _ scenario: String) {
        // Whole screen, not the app window: the keyboard and the lock overlay are
        // separate windows, and they are often what the scenario is about.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(scenario)-\(idiom)-\(variant)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Pre-existing audit findings, each tracked on GitHub: they don't fail a scenario,
    /// anything else does. Matched on the screens passed to `auditAccessibility` ("*" for
    /// chrome on every screen, like the iPad sidebar), the audit description and one of the
    /// element labels ("?" when the audit names no element; a trailing "*" matches a prefix,
    /// for labels holding dates or amounts). Keep labels exact: a broad pattern would hide a
    /// new finding on the same screen. Delete an entry when its issue is fixed.
    static let knownAccessibilityIssues: [(screen: String, description: String, labels: [String], issue: Int)] = [
        ("*", "Text clipped", ["Home", "Settings"], 219),
        ("*", "Dynamic Type font sizes are partially unsupported", ["Settings", "New"], 219),

        ("Home", "Hit area is too small", ["Dismiss"], 266),
        ("Home", "Hit area is too small", ["Dismiss reminder prompt"], 267),
        ("Home", "Text clipped", ["until *"], 268),
        ("Home", "Potentially inaccessible text", ["?"], 269),
        // iPad Recent Transactions rows (SampleData names, their categories and amounts).
        ("Home", "Dynamic Type font sizes are partially unsupported", [
            "Recent Transactions", "-€*", "+€*",
            "Morning coffee", "Lunch at bistro", "Monthly salary", "Weekly groceries", "Gas station", "Netflix subscription",
            "Coffee & Drinks", "Restaurants", "Salary", "Groceries", "Streaming Services", "Gas",
        ], 275),

        // Category chips in the inline strip and the More chip.
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", defaultCategoryNames + ["More"], 271),
        ("AddTransaction", "Text clipped", defaultCategoryNames, 271),
        // The amount field and its currency symbol.
        ("AddTransaction", "Element has no description", [""], 272),
        ("AddTransaction", "Dynamic Type font sizes are unsupported", ["", "€"], 272),
        ("AddTransaction", "Text clipped", [""], 272),
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", ["Cancel"], 273),
        ("AddTransaction", "Text clipped", ["New Transaction"], 273),
        ("AddTransaction", "Dynamic Type font sizes are partially unsupported", ["Group a trip's expenses*"], 274),

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
    @MainActor
    func auditAccessibility(_ app: XCUIApplication, _ scenario: String, screens: String...) throws {
        var failures: [String] = []
        var contrast: [String] = []
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? "?"
            let line = "\(issue.compactDescription) — '\(label)'"
            if issue.auditType == .contrast {
                contrast.append(line)
            } else if !Self.isKnown(screens, issue.compactDescription, label) {
                failures.append(line)
            }
            return true
        }
        if !contrast.isEmpty {
            let report = XCTAttachment(string: contrast.joined(separator: "\n"))
            report.name = "\(scenario)-contrast-\(idiom)-\(variant).txt"
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
                    pattern.hasSuffix("*") ? label.hasPrefix(pattern.dropLast()) : label == pattern
                }
        }
    }

    private var idiom: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    /// Set by `scripts/xcb scenarios` per pass; labels the attachments.
    private var variant: String {
        ProcessInfo.processInfo.environment["SCENARIO_VARIANT"] ?? ""
    }
}
