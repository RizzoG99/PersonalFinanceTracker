//
//  ReceiptTextRecognizer.swift
//  PersonalFinanceTraker
//
//  Thin Vision wrapper: image(s) in, a `ReceiptDocument` out. Kept separate from ReceiptParser
//  (which stays pure Swift/testable) since this needs UIKit + Vision and can't run in a fixture test.
//  See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import DataDetection
import UIKit
import Vision

enum ReceiptTextRecognizer {
    /// Recognizes text in one image with `RecognizeDocumentsRequest` (iOS 26), which runs layout
    /// analysis on top of OCR: as well as the flat line list `RecognizeTextRequest` used to give
    /// us, it returns the receipt's *tables* with label and price already paired per row. That
    /// pairing is the thing `ReceiptParser` previously had to reconstruct by guessing which order
    /// Vision happened to emit the two columns in.
    ///
    /// Language stays pinned to `it-IT` rather than auto-detected — see the plan's Prior art notes
    /// on why auto-detection is avoided for a cropped, noisy receipt photo.
    static func recognize(in image: UIImage) async throws -> ReceiptDocument {
        // `UIImage.cgImage` is raw pixel data with no rotation awareness — `imageOrientation` is a
        // separate display-time flag a bare CGImage never carries, so a sideways library photo
        // (confirmed real miss, 2026-08-28: a receipt shot in landscape via "Choose Photo") reads
        // as sideways text to Vision and returns nothing. The document scanner's own captures are
        // already upright, so this is a no-op there; it only matters for the photo-library path.
        guard let cgImage = image.normalizedOrientation().cgImage else { return ReceiptDocument() }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "it-IT")]
        request.textRecognitionOptions.useLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        var document = ReceiptDocument()
        for observation in observations {
            append(observation.document.text, to: &document)
            document.rows.append(contentsOf: observation.document.tables.flatMap(rows(in:)))
        }
        return document
    }

    /// Multi-page capture (e.g. an itemized receipt plus its separate card-authorization slip,
    /// scanned together) — concatenates every page's lines and rows before parsing, per the plan's
    /// multi-page edge case.
    static func recognize(in images: [UIImage]) async throws -> ReceiptDocument {
        var combined = ReceiptDocument()
        for image in images {
            let page = try await recognize(in: image)
            // Amount keys are indices into `lines`, so they shift by however many lines the pages
            // before this one contributed.
            let offset = combined.lines.count
            combined.lines.append(contentsOf: page.lines)
            combined.rows.append(contentsOf: page.rows)
            combined.detectedDates.append(contentsOf: page.detectedDates)
            for (index, amount) in page.detectedAmounts { combined.detectedAmounts[index + offset] = amount }
            // Heights are normalized per page, so they're only comparable within one — fine for the
            // merchant name, which is read off page 1.
            for (index, height) in page.lineHeights { combined.lineHeights[index + offset] = height }
        }
        return combined
    }

    /// Appends one text container's lines, and the data-detector results anchored to those lines.
    ///
    /// The detector reports each match with a bounding region rather than a line number, so a money
    /// match is tied back to a line by vertical overlap — the match's midpoint falling inside that
    /// line's box. Where a line carries several amounts (`2 x 1,50   3,00`) the rightmost wins,
    /// since that's the price column.
    private static func append(_ text: DocumentObservation.Container.Text, to document: inout ReceiptDocument) {
        let offset = document.lines.count
        let observations = text.lines
        let recognized = observations.compactMap { $0.topCandidates(1).first?.string }
        guard recognized.count == observations.count, !recognized.isEmpty else {
            // Belt and braces: if any line has no candidate the indices no longer line up, so fall
            // back to the transcript for text and skip the position-dependent detector results.
            document.lines.append(contentsOf: recognized.isEmpty
                ? text.transcript.components(separatedBy: .newlines)
                : recognized)
            document.detectedDates.append(contentsOf: detectedDates(in: text))
            return
        }
        document.lines.append(contentsOf: recognized)
        document.detectedDates.append(contentsOf: detectedDates(in: text))
        for (index, observation) in observations.enumerated() {
            document.lineHeights[index + offset] = Double(observation.boundingRegion.boundingBox.height)
        }

        var rightmostX: [Int: CGFloat] = [:]
        for detected in text.detectedData {
            guard case .moneyAmount(let money) = detected.match.details else { continue }
            let box = detected.boundingRegion.boundingBox
            let midY = box.origin.y + box.height / 2
            guard let index = observations.firstIndex(where: { observation in
                let lineBox = observation.boundingRegion.boundingBox
                return midY >= lineBox.origin.y && midY <= lineBox.origin.y + lineBox.height
            }) else { continue }
            if let existing = rightmostX[index], existing >= box.origin.x { continue }
            rightmostX[index] = box.origin.x
            document.detectedAmounts[index + offset] = money.amount
        }
    }

    private static func detectedDates(in text: DocumentObservation.Container.Text) -> [Date] {
        text.detectedData.compactMap { detected in
            guard case .calendarEvent(let event) = detected.match.details else { return nil }
            return event.startDate
        }
    }

    /// Flattens one detected table into label/amount pairs. A receipt's item table is two useful
    /// columns (description, price) but Vision may split it into more (quantity, VAT class), so
    /// the *last* cell that is purely an amount is the price and everything before it is the label.
    private static func rows(in table: DocumentObservation.Container.Table) -> [ReceiptRow] {
        table.rows.compactMap { cells in
            let texts = cells.map { $0.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let amountIndex = texts.lastIndex(where: { ReceiptParser.bareAmount(in: $0) != nil }),
                  let amount = ReceiptParser.bareAmount(in: texts[amountIndex]) else { return nil }
            let label = texts[..<amountIndex].filter { !$0.isEmpty }.joined(separator: " ")
            guard !label.isEmpty else { return nil }
            return ReceiptRow(label: label, amount: amount)
        }
    }
}

private extension UIImage {
    /// Redraws into a fresh bitmap so the pixel buffer itself is upright, rather than relying on
    /// callers (Vision included) to honor `imageOrientation` — the one property a raw `cgImage`
    /// strips away. A no-op cost-wise when already `.up` (every document-scanner capture).
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
