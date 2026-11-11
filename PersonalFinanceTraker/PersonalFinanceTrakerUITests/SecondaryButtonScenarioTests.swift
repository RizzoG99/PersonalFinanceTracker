//
//  SecondaryButtonScenarioTests.swift
//  PersonalFinanceTrakerUITests
//
//  #215: secondary (bordered) buttons share one neutral style and read at ≥ 4.5:1 in light,
//  dark and the largest text size; primary buttons stay indigo. S1–S5 are the contract in the
//  issue (S4, light unchanged, is the light-pass screenshots via shots-diff); S6–S8 cover the
//  other screens using the style, as the owner asked. The accessibility audit reports contrast
//  but doesn't enforce it on glass (#224), so contrast is measured from each button's pixels.
//  Every test shoots before it asserts, so a red run still leaves its screenshots.
//

import XCTest

final class SecondaryButtonScenarioTests: ScenarioTestCase {

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private let pendingCheckIn = ["-seedPendingCheckIn"]

    @MainActor
    func testS1_financialPulseSecondaryButtonsAreReadable() throws {
        let app = launchApp(pendingCheckIn)
        // 60 s: a pass's first launch after a simulator cold boot can stall the main thread 30 s+ (#341).
        XCTAssertTrue(button(app, beginningWith: "Log Morning coffee").waitForExistence(timeout: 60), "Financial Pulse isn't pending with quick templates")

        var readings: [Reading] = []
        for (name, predicate) in [
            ("Log Bus ticket", Self.label(beginningWith: "Log Bus ticket")),
            ("New transaction", Self.label("Add new transaction")),
            ("Set reminder", Self.label("Set")),
        ] {
            let target = app.buttons.matching(predicate).firstMatch
            scrollUntilHittable(app, target, in: scrollView(app, containing: predicate))
            readings.append(try settledMeasure(target, name, "S1"))
        }
        shoot(app, "S1")
        assertSecondary(readings, "S1")
        try auditAccessibility(app, "S1", screens: "Home")
    }

    @MainActor
    func testS2_siriGuideCopyButtonsAreReadable() throws {
        let app = launchApp()
        openSettings(app)
        let guide = app.buttons["Siri & Widgets"]
        scrollUntilHittable(app, guide, in: settingsList(app))
        guide.tap()

        let copyLabel = Self.label("Copy")
        let copy = app.buttons.matching(copyLabel).firstMatch
        scrollUntilHittable(app, copy, in: scrollView(app, containing: copyLabel))
        var readings = [try settledMeasure(copy, "Copy", "S2")]
        copy.tap()
        let copied = app.buttons["Copied"].firstMatch
        XCTAssertTrue(copied.waitForExistence(timeout: 5), "Copy didn't turn into Copied")
        readings.append(try settledMeasure(copied, "Copied", "S2"))
        shoot(app, "S2")
        assertSecondary(readings, "S2")
        try auditAccessibility(app, "S2", screens: "Settings", "SiriGuide")
    }

    @MainActor
    func testS3_primaryLogButtonStaysIndigo() throws {
        let app = launchApp(pendingCheckIn)
        let predicate = Self.label(beginningWith: "Log Morning coffee")
        let primary = app.buttons.matching(predicate).firstMatch
        scrollUntilHittable(app, primary, in: scrollView(app, containing: predicate))
        let fill = try settledMeasure(primary, "Log Morning coffee", "S3").fill
        shoot(app, "S3")
        XCTAssertTrue(fill.b > fill.r + 0.1 && fill.b > fill.g + 0.15, "the primary Log button lost its indigo fill: \(fill)")
    }

    @MainActor
    func testS5_backUpNowIsReadable() throws {
        let app = launchApp()
        openSettings(app)
        let backUp = app.buttons["Back Up Now"]
        scrollUntilHittable(app, backUp, in: settingsList(app))
        let reading = try settledMeasure(backUp, "Back Up Now", "S5")
        shoot(app, "S5")
        assertSecondary([reading], "S5")
        try auditAccessibility(app, "S5", screens: "Settings")
    }

    /// What's New: a release item's action on its raised card. `-whatsNewFixture` pins the built-in
    /// Financial Pulse release, so remote manifest edits can't change what is measured.
    @MainActor
    func testS6_whatsNewActionIsReadable() throws {
        let app = launchApp(["-whatsNewFixture"])
        openSettings(app)
        let whatsNew = app.buttons.matching(Self.label(beginningWith: "What's New")).firstMatch
        scrollUntilHittable(app, whatsNew, in: settingsList(app))
        whatsNew.tap()

        let predicate = Self.label("Open Home")
        let action = app.buttons.matching(predicate).firstMatch
        scrollUntilHittable(app, action, in: scrollView(app, containing: predicate))
        let reading = try settledMeasure(action, "Open Home", "S6")
        shoot(app, "S6")
        assertSecondary([reading], "S6")
    }

    /// #206's fixed-expense cards, now on the shared style: "Not fixed" beside the prominent answer.
    @MainActor
    func testS7_fixedExpenseNotFixedIsReadable() throws {
        let app = launchApp(["-seedFixedExpenseCards", "-fixedExpenseSuggestionsOnly"])
        if isPad {
            app.collectionViews["Sidebar"].staticTexts["Recurring"].firstMatch.tap()
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar never appeared")
            app.tabBars.buttons["Plan"].tap()
        }
        let predicate = Self.label("Not fixed")
        let notFixed = app.buttons.matching(predicate).firstMatch
        // iPad Recurring is a List (a collection view), iPhone Plan a scroll view.
        let host = isPad ? app.collectionViews.containing(predicate).firstMatch : scrollView(app, containing: predicate)
        scrollUntilHittable(app, notFixed, in: host)
        let reading = try settledMeasure(notFixed, "Not fixed", "S7")
        shoot(app, "S7")
        assertSecondary([reading], "S7")
    }

    /// The receipt's "Which total is right?" chips in Add Transaction.
    @MainActor
    func testS8_receiptTotalChipsAreReadable() throws {
        let app = launchApp(["-seedReceiptTotalCandidates"])
        let add = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30), "no Add transaction button")
        add.tap()
        let predicate = Self.label(beginningWith: "€12")
        let chip = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "no receipt total chips")
        scrollUntilHittable(app, chip, in: app.collectionViews.containing(predicate).firstMatch)
        // No "." in the name: the exporter takes what follows it for the file extension.
        let reading = try settledMeasure(chip, "Receipt total chip", "S8")
        shoot(app, "S8")
        assertSecondary([reading], "S8")
    }

    /// CSV import's category step: "Auto-Map All" in the toolbar. `-seedCSVImport` opens the wizard
    /// on a fixture file; iPhone reaches the step with Continue, iPad with the step picker.
    @MainActor
    func testS9_csvAutoMapIsReadable() throws {
        let app = launchApp(["-seedCSVImport"])
        if isPad {
            let categories = app.segmentedControls.buttons["Categories"]
            XCTAssertTrue(categories.waitForExistence(timeout: 30), "the iPad import sheet has no Categories step")
            categories.tap()
        } else {
            let next = app.buttons["Continue"]
            XCTAssertTrue(next.waitForExistence(timeout: 30), "the import wizard didn't open on its column step")
            next.tap()
        }
        let autoMap = app.buttons["Auto-Map All"]
        XCTAssertTrue(autoMap.waitForExistence(timeout: 10), "no Auto-Map All on the category step")
        let reading = try settledMeasure(autoMap, "Auto-Map All", "S9")
        shoot(app, "S9")
        assertSecondary([reading], "S9")
    }

    // MARK: - Steps

    private static func label(_ exact: String) -> NSPredicate {
        NSPredicate(format: "label == %@", exact)
    }

    private static func label(beginningWith prefix: String) -> NSPredicate {
        NSPredicate(format: "label BEGINSWITH %@", prefix)
    }

    private func button(_ app: XCUIApplication, beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(Self.label(beginningWith: prefix)).firstMatch
    }

    /// The scroll view holding the target: with a sheet up, Home's own scroll view is still in the tree.
    private func scrollView(_ app: XCUIApplication, containing predicate: NSPredicate) -> XCUIElement {
        app.scrollViews.containing(predicate).firstMatch
    }

    /// Settings is a Form (a collection view) and the only one holding the appearance picker; on
    /// iPad the sidebar is a collection view too, so "first" would pick the wrong list.
    private func settingsList(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews.containing(.segmentedControl, identifier: nil).firstMatch
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        if isPad {
            let settings = app.collectionViews["Sidebar"].staticTexts["Settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 30), "no Settings entry in the sidebar")
            settings.tap()
        } else {
            let open = app.buttons["Open profile"]
            XCTAssertTrue(open.waitForExistence(timeout: 30), "no Settings button on Home")
            open.tap()
        }
        XCTAssertTrue(app.segmentedControls.buttons["Auto"].waitForExistence(timeout: 10), "Settings never opened")
    }

    /// Short fixed drags: lists are lazy, and at AX-XXXL a full swipe flies past the row. The list
    /// is resolved once and dragged by screen position: its query matches on content, which a
    /// lazy list drops once scrolled away (Settings is ~25 screens long at AX-XXXL).
    @MainActor
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement, in scrollable: XCUIElement) {
        if element.waitForExistence(timeout: 2) && element.isHittable && fullyOnScreen(app, element) { return }
        let frame = scrollable.waitForExistence(timeout: 5) ? scrollable.frame : app.windows.firstMatch.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.75))
        let end = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.25))
        for _ in 0..<30 {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            if element.waitForExistence(timeout: 1) && element.isHittable && fullyOnScreen(app, element) { return }
        }
        XCTFail("\(element) never became fully visible")
    }

    /// Hittable only needs the centre on screen; the measurement needs the whole button.
    private func fullyOnScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        app.windows.firstMatch.frame.insetBy(dx: 0, dy: 40).contains(element.frame)
    }

    // MARK: - Contrast

    private struct Reading {
        let name: String
        let ratio: Double
        let fill: (r: Double, g: Double, b: Double)
        /// Sampling checks, kept as data and asserted only after the attachments and the
        /// screenshot, so a bad sample still leaves its evidence.
        let problems: [String]
    }

    /// Readable (≥ 4.5:1, WCAG text) and neutral: a grey fill shows no indigo cast. On glass the
    /// card shows through the translucent fill, so "neutral" allows a little blue. Calibrated on
    /// the red run: #206's grey "Not fixed" over dark indigo glass measured 0.064–0.066 of blue
    /// excess, the indigo `.bordered` fills 0.14–0.21; 0.10 sits between them.
    private func assertSecondary(_ readings: [Reading], _ scenario: String) {
        for reading in readings {
            XCTAssert(reading.problems.isEmpty, "\(scenario): '\(reading.name)' wasn't sampled: \(reading.problems)")
            let fill = reading.fill
            XCTAssertGreaterThanOrEqual(
                reading.ratio, 4.5,
                "\(scenario): '\(reading.name)' reads at \(String(format: "%.2f", reading.ratio)):1 on fill \(fill)"
            )
            XCTAssertLessThan(
                fill.b - max(fill.r, fill.g), 0.10,
                "\(scenario): '\(reading.name)' fill is tinted, not neutral: \(fill)"
            )
        }
    }

    /// Measures until two readings agree, so a scroll or the Copy → Copied change has settled,
    /// and attaches the reading and the measured band for the review.
    @MainActor
    private func settledMeasure(_ element: XCUIElement, _ name: String, _ scenario: String) throws -> Reading {
        var last = try measure(element, name)
        for _ in 0..<10 {
            let next = try measure(element, name)
            defer { last = next }
            if abs(next.reading.ratio - last.reading.ratio) < 0.05 { break }
        }
        // Device and pass in the name, like `shoot`'s: otherwise each pass overwrites the last.
        let pass = "\(isPad ? "ipad" : "iphone")-\(ProcessInfo.processInfo.environment["SCENARIO_VARIANT"] ?? "")"
        let note = XCTAttachment(string: "\(name): \(String(format: "%.2f", last.reading.ratio)):1, fill \(last.reading.fill)")
        note.name = "\(scenario)-SecondaryButton-measured-\(name)-\(pass).txt"
        note.lifetime = .keepAlways
        add(note)
        let crop = XCTAttachment(image: UIImage(cgImage: last.band))
        crop.name = "\(scenario)-SecondaryButton-band-\(name)-\(pass)"
        crop.lifetime = .keepAlways
        add(crop)
        return last.reading
    }

    /// WCAG contrast between a button's fill and its label, read from its pixels.
    /// - Band: the middle fifth of rows and the inner 90 % of columns. The capsule spans it even
    ///   when the hit frame is taller (Copy's `frame(minHeight: 44)`), so the card stays out.
    /// - Fill: the most common colour (5 bits per channel). It must cover a quarter of the band,
    ///   or the band isn't on the button.
    /// - Label: the foreground (text, icon and amount share one colour). Its contrast is the
    ///   highest pixel's, and at least 0.5 % of the band must come within 10 % of it, so one
    ///   stray highlight can't pass for text.
    @MainActor
    private func measure(_ element: XCUIElement, _ name: String) throws -> (reading: Reading, band: CGImage) {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let bandRect = CGRect(
            x: image.width / 20, y: image.height * 2 / 5,
            width: image.width * 9 / 10, height: max(1, image.height / 5)
        )
        let band = try XCTUnwrap(image.cropping(to: bandRect))
        let width = band.width, height = band.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: height))

        var colours: [(r: Double, g: Double, b: Double)] = []
        var buckets: [Int: [Int]] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let colour = (r: Double(pixels[index]) / 255, g: Double(pixels[index + 1]) / 255, b: Double(pixels[index + 2]) / 255)
            buckets[Int(colour.r * 31) << 10 | Int(colour.g * 31) << 5 | Int(colour.b * 31), default: []].append(colours.count)
            colours.append(colour)
        }
        var problems: [String] = []
        let fillPixels = try XCTUnwrap(buckets.values.max { $0.count < $1.count }).map { colours[$0] }
        if fillPixels.count * 4 <= colours.count { problems.append("no dominant fill in the measured band") }
        let count = Double(fillPixels.count)
        let fill = (
            r: fillPixels.reduce(0) { $0 + $1.r } / count,
            g: fillPixels.reduce(0) { $0 + $1.g } / count,
            b: fillPixels.reduce(0) { $0 + $1.b } / count
        )
        let fillLuminance = Self.luminance(fill)
        let contrasts = colours.map { Self.contrast(Self.luminance($0), fillLuminance) }
        let ratio = contrasts.max() ?? 1
        let foreground = contrasts.filter { $0 >= 1 + (ratio - 1) * 0.9 }.count
        if foreground * 200 <= colours.count { problems.append("no label in the measured band") }
        return (Reading(name: name, ratio: ratio, fill: fill, problems: problems), band)
    }

    private static func luminance(_ pixel: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(pixel.r) + 0.7152 * linear(pixel.g) + 0.0722 * linear(pixel.b)
    }

    private static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
