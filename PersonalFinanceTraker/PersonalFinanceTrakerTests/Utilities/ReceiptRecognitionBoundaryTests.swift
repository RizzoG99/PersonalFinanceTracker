import Foundation
import Testing
import UIKit
@testable import PersonalFinanceTraker

/// Run alone: captures the actual async recognizer execution, unlike the synchronous
/// transform harness. Synthetic text only; private-receipt accuracy is a separate gate.
@Suite(.serialized)
struct ReceiptRecognitionBoundaryTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_RECEIPT_RECOGNITION_BASELINE"] == "1"
                   && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"))
    @MainActor func actualRecognizerBoundaries() async throws {
        let previous = PerformanceAuditRecorder.isEnabled
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: previous) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
            for (index, text) in ["PERF301 TEST", "DOCUMENTO COMMERCIALE", "TOTALE 12,34"].enumerated() {
                (text as NSString).draw(at: CGPoint(x: 100, y: 150 + index * 300), withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 100, weight: .regular), .foregroundColor: UIColor.black
                ])
            }
        }
        PerformanceAuditRecorder.resetForTesting(isEnabled: true)
        let document = try await ReceiptImageAudit.$request.withValue("synthetic-recognizer") {
            try await ReceiptTextRecognizer.recognize(in: image)
        }
        let snapshot = PerformanceAuditRecorder.testingSnapshot()
        #expect(snapshot.counters["Receipt.ocr.plain.completed"] == 1)
        #expect(snapshot.counters["Receipt.ocr.enhanced.completed"] == 1)
        #expect(snapshot.counters["Receipt.ocr.prepared"] == 1)
        #expect(snapshot.activeIntervals.values.allSatisfy { $0 == 0 })
        #expect(!document.lines.isEmpty)
        let samples = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.synchronousSamples))
        let record: [String: Any] = ["samples": samples, "synthetic_only": true,
            "plain_wall_ns": snapshot.totalDurationNanoseconds["Receipt.ocr.plain"] ?? 0,
            "enhanced_wall_ns": snapshot.totalDurationNanoseconds["Receipt.ocr.enhanced"] ?? 0]
        Attachment.record(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted]),
                          named: "perf301-recognizer-boundaries.json")
    }
}

/// Opt in after copying TEST app exports + human expectations into ignored Fixture/Receipts.
/// Missing or incomplete data FAILS when opted in; ordinary CI reports an explicit skip.
@Suite(.serialized)
struct ReceiptImageDeviceFixtureTests {
    struct Expected: Decodable {
        let id: String
        let total: String
        let date: [Int]?
        let merchant: String?
    }
    struct Capture: Decodable {
        let original: String
        let quad: [[Double]]?
        let quad_already_padded: Bool
        let orientation: Int
        let pixel_width: Int
        let pixel_height: Int
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_RECEIPT_FIXTURES"] == "1"))
    @MainActor func capturedReceiptsPreserveExpectedFields() async throws {
        let previous = PerformanceAuditRecorder.isEnabled
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: previous) }
        let urls = ReceiptFixtures.bundle.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? []
        func file(_ name: String) throws -> URL {
            try #require(urls.first { $0.lastPathComponent == name }, "Missing private fixture resource: \(name)")
        }
        let expectations = try JSONDecoder().decode([Expected].self,
            from: Data(contentsOf: file("perf301-expectations.json")))
        #expect(!expectations.isEmpty)
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(DateComponents(calendar: calendar, year: 2026, month: 10, day: 16).date)
        for expected in expectations {
            let capture = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: file("\(expected.id).json")))
            #expect(capture.quad_already_padded)
            let image = try #require(UIImage(data: Data(contentsOf: file(capture.original))))
            #expect(image.imageOrientation.rawValue == capture.orientation)
            #expect(image.cgImage?.width == capture.pixel_width)
            #expect(image.cgImage?.height == capture.pixel_height)
            let quad = try capture.quad.map { points in
                try points.map { point in
                    try #require(point.count == 2 && point.allSatisfy { $0.isFinite })
                    return CGPoint(x: point[0], y: point[1])
                }
            }
            if let quad { try #require(quad.count == 4) }
            PerformanceAuditRecorder.resetForTesting(isEnabled: true)
            let document = try await ReceiptImageAudit.$request.withValue(expected.id) {
                let cropped = ReceiptCameraModel.processedPhoto(image, normalizedQuad: quad)
                Attachment.record(try #require(cropped.jpegData(compressionQuality: 0.9)),
                                  named: "perf301-device-\(expected.id)-crop.jpg")
                return try await ReceiptTextRecognizer.recognize(in: cropped)
            }
            let scan = ReceiptParser.parse(document, now: now)
            // Private corpus output stays inside the ignored xcresult. This records every
            // replay even when a field assertion fails; expectations come from the photo.
            let replay: [String: Any] = [
                "id": expected.id, "total": scan.total.map { "\($0)" } ?? "",
                "merchant": scan.merchant ?? "", "lines": document.lines,
                "date": scan.date.map { "\($0)" } ?? ""
            ]
            Attachment.record(try JSONSerialization.data(withJSONObject: replay, options: [.sortedKeys]),
                              named: "perf301-device-\(expected.id).json")
            let expectedTotal = try #require(Decimal(string: expected.total))
            if scan.total != expectedTotal || expected.merchant.map({ scan.merchant != $0 }) == true {
                // Diagnostic control only: retain the failing crop oracle and compare the
                // same recognizer on original pixels. Never substitute this for its result.
                let originalDocument = try await ReceiptTextRecognizer.recognize(in: image)
                let originalScan = ReceiptParser.parse(originalDocument, now: now)
                let control: [String: Any] = [
                    "id": expected.id, "control": "original_without_crop",
                    "total": originalScan.total.map { "\($0)" } ?? "",
                    "merchant": originalScan.merchant ?? "", "lines": originalDocument.lines
                ]
                Attachment.record(try JSONSerialization.data(withJSONObject: control, options: [.sortedKeys]),
                                  named: "perf301-device-\(expected.id)-original-control.json")
            }
            #expect(scan.total == expectedTotal)
            if let merchant = expected.merchant { #expect(scan.merchant == merchant) }
            if let date = expected.date {
                try #require(date.count == 3)
                let expectedDate = DateComponents(calendar: calendar, year: date[0], month: date[1], day: date[2]).date
                #expect(scan.date == expectedDate)
                #expect(!scan.dateWasClamped)
            }
            #expect(!document.lines.isEmpty)
            #expect(PerformanceAuditRecorder.testingSnapshot().activeIntervals.values.allSatisfy { $0 == 0 })
        }
        Attachment.record(Data("{\"replayed_fixtures\":\(expectations.count)}".utf8),
                          named: "perf301-device-replay-count.json")
    }
}
