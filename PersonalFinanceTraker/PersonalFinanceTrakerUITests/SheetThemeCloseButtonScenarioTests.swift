//
//  SheetThemeCloseButtonScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #158: switching theme inside the Settings sheet must restyle its Close button at once,
//  not only after the sheet is reopened. The tester's screenshot shows the glass circle
//  behind the X staying light in Dark, which no accessibility value exposes, so the tests
//  compare the button's pixels with the same button in a freshly opened sheet.
//

import UIKit
import XCTest

final class SheetThemeCloseButtonScenarioTests: ScenarioTestCase {

    @MainActor
    func testS1_closeButtonFollowsThemeWhileSheetIsOpen() throws {
        try XCTSkipIf(isPad, "iPad hosts Settings in the detail column, not in a sheet")
        let app = launchApp()
        let close = app.buttons["Close"]

        openSettings(app)
        select("Dark", app)
        reopenSettings(app)
        let freshDark = try settledLuminance(close)
        select("Light", app)
        reopenSettings(app)
        let freshLight = try settledLuminance(close)
        XCTAssertGreaterThan(abs(freshLight - freshDark), 0.2, "themes look alike, so this test could not see the bug")

        select("Dark", app)
        try assertLuminance(of: close, near: freshDark, "Close button kept its Light look after switching to Dark")
        shoot(app, "S1-dark")

        select("Light", app)
        try assertLuminance(of: close, near: freshLight, "Close button kept its Dark look after switching to Light")
        shoot(app, "S1-light")
        // Last: the audit scrolls the Form, which would hide the picker from `select`.
        try auditAccessibility(app, "S1", screens: "Settings")
    }

    /// Auto is the default, so this is the route most testers take: the sheet opens on Auto
    /// and the first change goes straight to the theme the system is not using.
    @MainActor
    func testS2_closeButtonFollowsThemeToAndFromAuto() throws {
        try XCTSkipIf(isPad, "iPad hosts Settings in the detail column, not in a sheet")
        let app = launchApp()
        let close = app.buttons["Close"]

        openSettings(app)
        let freshAuto = try settledLuminance(close)
        select(oppositeTheme, app)
        reopenSettings(app)
        let freshOpposite = try settledLuminance(close)
        XCTAssertGreaterThan(abs(freshAuto - freshOpposite), 0.2, "themes look alike, so this test could not see the bug")
        select("Auto", app)
        reopenSettings(app)

        select(oppositeTheme, app)
        try assertLuminance(of: close, near: freshOpposite, "Close button kept its Auto look after switching to \(oppositeTheme)")
        shoot(app, "S2-opposite")

        select("Auto", app)
        try assertLuminance(of: close, near: freshAuto, "Close button kept its \(oppositeTheme) look after switching to Auto")
        shoot(app, "S2-auto")
        try auditAccessibility(app, "S2", screens: "Settings")
    }

    /// iPad has no Settings sheet, so there is no Close button: this guards the same theme
    /// change where iPad shows it, on the sidebar beside Settings. Measured on a crop of the
    /// screen, because the sidebar element briefly reports an empty frame during the change,
    /// and a screenshot of it then fails the test.
    @MainActor
    func testS3_sidebarFollowsThemeBesideSettingsOnIPad() throws {
        try XCTSkipUnless(isPad, "iPhone is covered by S1 and S2")
        let app = launchApp()
        let screen = XCUIScreen.main
        let sidebar = app.collectionViews["Sidebar"]
        let settings = sidebar.staticTexts["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "no Settings entry in the sidebar")
        settings.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Auto"].waitForExistence(timeout: 10), "Settings never opened")
        let region = sidebar.frame
        XCTAssertFalse(region.isEmpty, "sidebar has no frame to measure")
        let start = try settledLuminance(screen, region: region)

        select(oppositeTheme, app)
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in abs(((try? self.luminance(screen, region: region)) ?? start) - start) > 0.2 },
            object: nil
        )
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed, "sidebar did not restyle after switching to \(oppositeTheme)")
        shoot(app, "S3-opposite")

        select("Auto", app)
        try assertLuminance(of: screen, region: region, near: start, "sidebar did not return to its look after switching to Auto")
        shoot(app, "S3-auto")
        try auditAccessibility(app, "S3", screens: "Settings")
    }

    // MARK: - Helpers

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// The theme the simulator is not using, so choosing it visibly changes the app.
    private var oppositeTheme: String {
        ProcessInfo.processInfo.environment["SCENARIO_VARIANT"]?.hasPrefix("dark") == true ? "Light" : "Dark"
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let open = app.buttons["Open profile"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "no Settings button on Home")
        open.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "Settings sheet never opened")
    }

    @MainActor
    private func reopenSettings(_ app: XCUIApplication) {
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForNonExistence(timeout: 10), "Settings sheet did not close")
        openSettings(app)
    }

    @MainActor
    private func select(_ theme: String, _ app: XCUIApplication) {
        // Short drags: the Form is lazy, so at AX-XXXL a full swipe flies past the picker and
        // drops it from the tree.
        let segment = app.segmentedControls.buttons[theme]
        let form = app.collectionViews.firstMatch
        for _ in 0..<15 where !(segment.exists && segment.isHittable) {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        XCTAssertTrue(segment.isHittable, "no \(theme) segment in Settings")
        segment.tap()
    }

    @MainActor
    private func assertLuminance(
        of element: XCUIScreenshotProviding, region: CGRect? = nil, near expected: Double, _ message: String
    ) throws {
        var last = -1.0
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                last = (try? self.luminance(element, region: region)) ?? -1
                return abs(last - expected) < 0.1
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 5), .completed, "\(message): luminance \(last), expected \(expected)")
    }

    /// Reads until two samples agree, because the element exists before its sheet stops animating.
    @MainActor
    private func settledLuminance(_ element: XCUIScreenshotProviding, region: CGRect? = nil) throws -> Double {
        var samples = [try luminance(element, region: region)]
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let value = (try? self.luminance(element, region: region)) ?? -1
                let stable = abs(value - samples[samples.count - 1]) < 0.01
                samples.append(value)
                return stable
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 10), .completed, "never settled: \(samples)")
        return samples[samples.count - 1]
    }

    /// Mean luminance (0 black, 1 white) of what the element shows, the glass and the X together.
    /// `region` is in points and crops a screenshot of the whole screen.
    @MainActor
    private func luminance(_ element: XCUIScreenshotProviding, region: CGRect? = nil) throws -> Double {
        var image = try XCTUnwrap(element.screenshot().image.cgImage)
        if let region {
            let scale = CGFloat(image.width) / XCUIApplication().frame.width
            image = try XCTUnwrap(image.cropping(to: region.applying(CGAffineTransform(scaleX: scale, y: scale))))
        }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var sum = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return sum / Double(image.width * image.height) / 255
    }
}
