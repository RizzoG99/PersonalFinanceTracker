//
//  ReceiptEndToEndTests.swift
//  PersonalFinanceTrakerTests
//
//  Runs the *real* pipeline — Vision OCR + layout analysis, then ReceiptParser — over the receipt
//  photos in Fixture/Receipts. Every other receipt test feeds the parser line arrays transcribed by
//  hand from a past Vision run, so they can only catch parser regressions; they cannot see an OCR
//  miss, an orientation miss, or a Vision behaviour change between OS releases. This one can, and
//  it is the only test that answers "does scanning this receipt actually work".
//
//  Those photos are real receipts carrying real personal data (tax codes, card PANs, addresses), so
//  `Fixture/Receipts/` is gitignored and the images exist only on the machine that shot them. This
//  file is therefore committed but **skips itself** wherever the images are absent — CI, a fresh
//  clone, another contributor. It is a pre-release check you run locally, not a gate.
//
//  When a case fails it attaches the whole recognized `ReceiptDocument` — lines, short-side heights,
//  detected amounts, Vision table rows — to the failure message, which is what makes the result
//  bundle enough to debug from. That dump is also the raw material for a committable fixture: read
//  it, delete anything personal, paste the lines into `ReceiptParserTests`. Redaction stays a human
//  step on purpose; an automatic scrubber that misses one line commits a tax code to history forever.
//

import Foundation
import Testing
import UIKit
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct ReceiptEndToEndTests {

    /// Fixed rather than `.now`: the sane-date window is two years wide, so a real clock would
    /// eventually push the 2025 receipts out of range and fail the suite for no reason.
    private static let now = DateComponents(
        calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 29
    ).date!

    struct Expectation: CustomStringConvertible {
        let image: String
        let total: Decimal
        let date: DateComponents
        /// nil where the receipt genuinely prints no merchant name — the Galatina card slip carries
        /// only processor boilerplate, so whatever the parser picks there is a guess, not a fact.
        let merchant: String?

        var description: String { image }
    }

    static let receipts: [Expectation] = [
        .init(image: "barrueco", total: 13.00,
              date: .init(year: 2026, month: 8, day: 25), merchant: "Barrueco S.R.L"),
        .init(image: "autentica", total: 7.22,
              date: .init(year: 2026, month: 8, day: 28), merchant: nil),
        // Merchant unasserted: Vision reads the printed name as "CAMILLA-MU BAR", so no parser
        // change can produce "Camilla-Nu Bar" here. Asserting the misreading would only lock in an
        // OCR bug as if it were intended.
        .init(image: "camilla-nu-bar", total: 15.80,
              date: .init(year: 2026, month: 8, day: 27), merchant: nil),
        .init(image: "ottica-longo", total: 90.00,
              date: .init(year: 2026, month: 7, day: 25), merchant: "Ottica Longo"),
        .init(image: "puce-motorrad", total: 935.00,
              date: .init(year: 2025, month: 5, day: 27), merchant: "Puce Motorrad"),
        .init(image: "galatina", total: 219.80,
              date: .init(year: 2025, month: 11, day: 24), merchant: nil),
    ]

    /// True only on a machine that actually has the private photos, which is what the whole suite
    /// is gated on — everywhere else these tests report as skipped rather than red.
    static let fixturesAvailable = loadImage(named: receipts[0].image) != nil

    @Test(.enabled(if: fixturesAvailable), arguments: receipts)
    func scanningARealReceiptPhotoFindsTheTotalDateAndMerchant(_ expected: Expectation) async throws {
        let image = try #require(Self.loadImage(named: expected.image))
        let document = try await ReceiptTextRecognizer.recognize(in: image)
        let dump = Self.dump(document, for: expected.image)

        // Reported separately from the parse assertions below: an empty document means Vision read
        // nothing (orientation, focus, a runtime change), which is a different bug from the parser
        // picking the wrong line out of text it did receive.
        #expect(!document.lines.isEmpty, "\(expected.image): Vision recognized no text at all")

        let scan = ReceiptParser.parse(document, now: Self.now)

        #expect(
            scan.total == expected.total,
            "got \(String(describing: scan.total)), candidates \(scan.totalCandidates)\n\(dump)"
        )
        var components = expected.date
        components.calendar = Calendar(identifier: .gregorian)
        #expect(scan.date == components.date, "\(expected.image): date")
        #expect(scan.dateWasClamped == false, "\(expected.image): date was clamped")
        #expect(scan.isRefund == false, "\(expected.image): read as a refund")
        if let merchant = expected.merchant {
            #expect(scan.merchant == merchant, "got \(scan.merchant ?? "nil")\n\(dump)")
        }
    }

    /// Everything Vision returned, in one string, attached to whichever expectation fails. Built
    /// eagerly rather than lazily — a scan is seconds of OCR, a few hundred lines of string
    /// building is free next to that, and the alternative (a file) does not survive the cloned
    /// simulator xcodebuild deletes after a parallel test run.
    private static func dump(_ document: ReceiptDocument, for name: String) -> String {
        var text = "--- \(name): \(document.lines.count) lines ---\n"
        for (index, line) in document.lines.enumerated() {
            let height = document.lineHeights[index].map { String(format: " h=%.4f", $0) } ?? ""
            let detected = document.detectedAmounts[index].map { " $=\($0)" } ?? ""
            text += "[\(index)] \(line)\(height)\(detected)\n"
        }
        text += "rows: \(document.rows.map { "\($0.label)=\($0.amount)" })\n"
        text += "detectedDates: \(document.detectedDates)"
        return text
    }

    private static func loadImage(named name: String) -> UIImage? {
        guard let url = ReceiptFixtures.imageURL(named: name),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

/// Locates fixture files without assuming anything about the name Xcode copied them under.
///
/// Two surprises, both of which silently turned fixture-gated tests into *skips* rather than
/// failures — the dangerous direction, because the suite still exits 0:
///   - resource copying **flattens** the folder, so `Labels/` does not exist in the bundle;
///   - it **rewrites image extensions**, so `barrueco.JPG` ships as `barrueco.jpeg`.
/// So files are found by base name and by extension *set*, never by path or exact spelling.
enum ReceiptFixtures {
    static let bundle = Bundle(for: BundleToken.self)

    /// Matches on the base name alone: `barrueco` finds `barrueco.jpeg` as happily as `barrueco.JPG`.
    static func imageURL(named name: String) -> URL? {
        allURLs.first { $0.deletingPathExtension().lastPathComponent == name }
    }

    /// Every transcription in the corpus. Identified by suffix rather than by folder, since the
    /// `Labels/` directory does not survive the copy.
    static func labelURLs() -> [URL] {
        allURLs
            .filter { $0.pathExtension.lowercased() == "txt" && $0.lastPathComponent.hasSuffix("-receipt.txt") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static let allURLs: [URL] = {
        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
    }()
}

private final class BundleToken {}
