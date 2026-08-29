//
//  ReceiptTextRecognizer.swift
//  PersonalFinanceTraker
//
//  Thin Vision wrapper: image(s) in, a `ReceiptDocument` out. Kept separate from ReceiptParser
//  (which stays pure Swift/testable) since this needs UIKit + Vision and can't run in a fixture test.
//  See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import CoreImage.CIFilterBuiltins
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
        // No perspective correction. `VNDetectDocumentSegmentationRequest` + `CIPerspectiveCorrection`
        // was tried here, to replace the straightening the old VisionKit scanner made the user
        // confirm by hand. It cost us a receipt: on the `autentica` fixture the segmentation passed
        // a 0.5 confidence gate and then cropped the right-hand side away, taking the price column
        // with it — every line came back truncated ("TOTAL", "IMPOR", "28/08/") and the total read
        // as nil with no candidates, a silent miss. Raising the gate was not the fix, because the
        // damage is invisible to any cheap quality signal: the line *count* was normal, only the
        // content was cut. Vision reads handheld, moderately angled receipts perfectly well on its
        // own — all six well-lit fixtures pass on the uncorrected frame — so the correction was pure
        // downside. Revisit only with a fixture that actually fails without it.
        guard let cgImage = image.preparedForRecognition() else { return ReceiptDocument() }
        let plain = try await recognize(cgImage)

        // Low light does not produce *fewer* lines, it produces wrong characters, which is why an
        // earlier version of this that retried only when the page looked empty never once fired.
        // On the `scontrino` fixture the dim photo read a full 28 lines and still turned
        // "DOCUMENTO COMMERCIALE" into "LUCUMENTO COMMERCTALE" (which then won the merchant vote)
        // and the year 2026 into 2021. So both passes always run and Vision's own mean confidence
        // picks the winner — the parser has no way to tell a confident misreading from a good one,
        // but the recognizer does.
        //
        // ponytail: this doubles OCR time on every scan, roughly a second, behind a progress
        // indicator the user already sees. Gate it on the plain pass's confidence if that ever
        // becomes the complaint.
        guard let boosted = Self.enhanced(cgImage) else { return plain }
        let enhanced = try await recognize(boosted)
        return enhanced.meanConfidence > plain.meanConfidence ? enhanced : plain
    }

    private static func recognize(_ cgImage: CGImage) async throws -> ReceiptDocument {
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

    /// Boosts contrast and flattens the background the way the document scanner's black-and-white
    /// filter does. `CIDocumentEnhancer` is built for exactly this input, so no hand-rolled
    /// thresholding is needed.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static func enhanced(_ cgImage: CGImage) -> CGImage? {
        let filter = CIFilter.documentEnhancer()
        filter.inputImage = CIImage(cgImage: cgImage)
        filter.amount = 1
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
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
        // The *observation's* confidence, not the candidate's. `RecognizedText.confidence` exists
        // but `RecognizeDocumentsRequest` leaves it at zero, which made `meanConfidence` zero for
        // every scan — and since the plain/enhanced choice is a `>` comparison, the enhanced pass
        // could never win and the low-light path was dead from the day it was written (device log,
        // 2026-08-29). A metric that is silently zero is worse than no metric: it looks like a
        // working decision. `ReceiptEndToEndTests` now asserts this is populated.
        let confidences = observations.map(\.confidence)
        if !confidences.isEmpty {
            document.meanConfidence = Double(confidences.reduce(0, +)) / Double(confidences.count)
        }
        for (index, observation) in observations.enumerated() {
            // The box's **short side**, not its height. `boundingBox` is axis-aligned in page
            // coordinates, so for a receipt lying sideways in an otherwise upright photo (both
            // rotated fixtures, 2026-08-29) a line's `height` is really its *length* — which made
            // the longest line, not the biggest text, win the merchant vote and returned
            // "Totale Cohplessivo" as the shop name. The short side is the text height at either
            // orientation.
            // ponytail: min(w, h) covers 0°/90°, the two ways a receipt is ever photographed. Text
            // at a genuine diagonal overestimates; switch to the distance between the region's
            // topLeft and bottomLeft corners if that ever shows up in a real miss.
            let box = observation.boundingRegion.boundingBox
            document.lineHeights[index + offset] = Double(min(box.width, box.height))
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
    /// The longest side Vision is given. A modern camera's full 12MP is far more than receipt text
    /// needs, and every pixel is paid for three times over: this bitmap, then each of the two OCR
    /// passes.
    ///
    /// 2000 is measured, not guessed. At 1200 the fixtures fail with a *wrong amount*, not a missing
    /// one: Vision reads Puce Motorrad's "935,00" as "935,000", which parses as no amount at all, so
    /// the total falls through to the VAT line and 168,61 is returned confidently with no candidates
    /// flagged. 1600 passes, but it is one step above that cliff, and the memory argument for going
    /// lower is already spent — the 440MB blowup was the renderer scale, not the pixel count, and
    /// 2000px is a ~12MB bitmap. The extra margin is cheaper than a silently wrong total.
    static let recognitionMaxDimension: CGFloat = 2000

    /// Uprights and downscales in a single redraw, returning pixel data Vision can use directly.
    ///
    /// The scale of `1` is load-bearing, not tidiness. `UIGraphicsImageRendererFormat.default()`
    /// uses the *device* scale — 3 on a Pro Max — and a camera `UIImage` already reports its size in
    /// pixels with `scale == 1`. Rendering a 4032x3024 frame through the default format therefore
    /// produced a 12096x9072 bitmap, ~440MB, and the OS killed the app on device (2026-08-29). The
    /// old VisionKit scanner hid this: its output was already `.up`, so the rotation redraw that
    /// triggers it never ran.
    func preparedForRecognition() -> CGImage? {
        let longest = max(size.width, size.height)
        let ratio = longest > Self.recognitionMaxDimension ? Self.recognitionMaxDimension / longest : 1
        // Already upright and already small enough: hand back the pixels untouched.
        guard ratio < 1 || imageOrientation != .up else { return cgImage }

        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
