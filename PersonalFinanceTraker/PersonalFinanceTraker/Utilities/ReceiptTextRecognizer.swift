//
//  ReceiptTextRecognizer.swift
//  PersonalFinanceTraker
//
//  Thin Vision wrapper: image(s) in, recognized text lines out. Kept separate from ReceiptParser
//  (which stays pure Swift/testable) since this needs UIKit + Vision and can't run in a fixture test.
//  See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import UIKit
import Vision

enum ReceiptTextRecognizer {
    /// Recognizes text in one image, top-to-bottom reading order (Vision's default for
    /// `VNRecognizedTextObservation` results). `.accurate` + pinned `it-IT` — see the plan's Prior
    /// art notes on why auto-detection is avoided for a cropped, noisy receipt photo.
    static func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "it-IT")]
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    /// Multi-page capture (e.g. an itemized receipt plus its separate card-authorization slip,
    /// scanned together) — concatenates every page's lines before parsing, per the plan's
    /// multi-page edge case.
    static func recognizeLines(in images: [UIImage]) async throws -> [String] {
        var allLines: [String] = []
        for image in images {
            allLines.append(contentsOf: try await recognizeLines(in: image))
        }
        return allLines
    }
}
