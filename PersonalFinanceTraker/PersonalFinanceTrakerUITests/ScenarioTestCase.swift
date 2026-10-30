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
    /// anything else does. Matched on the screen passed to `auditAccessibility` ("*" for
    /// chrome on every screen, like the iPad sidebar), the audit description and the
    /// element label ("?" when the audit names no element; a trailing "*" matches a
    /// prefix, for labels holding dates or amounts). Delete an entry when its issue is fixed.
    static let knownAccessibilityIssues: [(screen: String, description: String, label: String, issue: Int)] = [
        ("Home", "Hit area is too small", "Dismiss", 266),
        ("Home", "Hit area is too small", "Dismiss reminder prompt", 267),
        ("Home", "Text clipped", "until *", 268),
        ("Home", "Potentially inaccessible text", "?", 269),
        ("*", "Text clipped", "Home", 219),
        ("*", "Text clipped", "Settings", 219),
        ("*", "Dynamic Type font sizes are partially unsupported", "Settings", 219),
        ("*", "Dynamic Type font sizes are partially unsupported", "New", 219),
    ]

    /// Objective accessibility gate for the screen on display (hit regions, clipped and
    /// Dynamic Type text, labels). Call it on every screen a scenario changes. Fails once
    /// with every new finding rather than stopping at the first.
    ///
    /// Contrast is reported, not enforced: on the glass cards its findings change from
    /// run to run (and SampleData's dates change the rows on screen), so they go to a
    /// `<scenario>-contrast-…txt` report for the screenshot review instead. See #224.
    @MainActor
    func auditAccessibility(_ app: XCUIApplication, _ scenario: String, screen: String) throws {
        var failures: [String] = []
        var contrast: [String] = []
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? "?"
            let line = "\(issue.compactDescription) — '\(label)'"
            if issue.auditType == .contrast {
                contrast.append(line)
            } else if !Self.isKnown(screen, issue.compactDescription, label) {
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
        XCTAssert(failures.isEmpty, "New accessibility issues in \(scenario) on \(screen):\n" + failures.joined(separator: "\n"))
    }

    private static func isKnown(_ screen: String, _ description: String, _ label: String) -> Bool {
        knownAccessibilityIssues.contains { known in
            (known.screen == "*" || known.screen == screen)
                && known.description == description
                && (known.label.hasSuffix("*")
                ? label.hasPrefix(known.label.dropLast())
                : label == known.label)
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
