import CryptoKit
import Darwin
import Foundation
import Testing
import UIKit
@testable import PersonalFinanceTraker

extension PerformanceRecorderSerialTests {
/// Run alone: recorder state is process-wide. This harness measures transforms on the
/// main actor, NOT the executing thread of the async recognizer, camera wait or a frame.
@Suite(.serialized)
@MainActor
struct ReceiptImageBaselineTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_RECEIPT_BASELINE"] == "1"
                   && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"))
    func highResolutionTransforms() throws {
        let previous = PerformanceAuditRecorder.isEnabled
        defer { PerformanceAuditRecorder.resetForTesting(isEnabled: previous) }
        let source = try #require(Self.syntheticReceipt().jpegData(compressionQuality: 0.95))
        let full = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        let partial = [CGPoint(x: 0.25, y: 0.75), CGPoint(x: 0.75, y: 0.75),
                       CGPoint(x: 0.75, y: 0.25), CGPoint(x: 0.25, y: 0.25)]
        let diamond = [CGPoint(x: 0.5, y: 1), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 0, y: 0.5)]
        let tiny = [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.45, y: 0.4),
                    CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.4, y: 0.45)]
        let cases: [(String, UIImage.Orientation, [CGPoint]?)] = [
            ("up.noQuad", .up, nil), ("right.noQuad", .right, nil),
            ("up.full", .up, full), ("right.full", .right, full),
            ("left.partial", .left, partial), ("down.diamond", .down, diamond),
            ("right.invalid", .right, tiny), ("up.edge", .up, ReceiptCameraModel.padded(partial))
        ]
        var records: [[String: Any]] = []
        for (name, orientation, quad) in cases {
            var reference: String?
            // 0 is first transform use for this case; -1 is the disabled control;
            // 1...5 are warm repeats. Fixture creation is outside all timed scopes.
            for round in [0, -1, 1, 2, 3, 4, 5] {
                try autoreleasepool {
                    let decoded = try #require(UIImage(data: source)?.cgImage)
                    let image = UIImage(cgImage: decoded, scale: 1, orientation: orientation)
                    PerformanceAuditRecorder.resetForTesting(isEnabled: round >= 0)
                    let before = Self.highWaterBytes()
                    let (cropped, prepared) = try ReceiptImageAudit.$request.withValue("\(name).\(round)") {
                        let cropped = ReceiptCameraModel.processedPhoto(image, normalizedQuad: quad)
                        let prepared = try #require(cropped.preparedForRecognition())
                        return (cropped, prepared)
                    }
                    let after = Self.highWaterBytes()
                    let snapshot = PerformanceAuditRecorder.testingSnapshot()
                    #expect(snapshot.activeIntervals.values.allSatisfy { $0 == 0 })
                    #expect(snapshot.synchronousSamples.allSatisfy { $0.isMainThread })
                    #expect(max(prepared.width, prepared.height) <= 2000)
                    #expect(snapshot.counters["Receipt.crop.total.start", default: 0] == (round >= 0 && quad != nil ? 1 : 0))
                    #expect(snapshot.counters["Receipt.ocr.prepare.start", default: 0] == (round >= 0 ? 1 : 0))
                    let digest = try Self.digest(cropped) + Self.digest(UIImage(cgImage: prepared))
                    if let reference { #expect(digest == reference, "Pixel parity with disabled control: \(name) round \(round)") }
                    else { reference = digest }
                    let samples = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.synchronousSamples))
                    let record: [String: Any] = [
                        "case": name, "round": round, "orientation": orientation.rawValue,
                        "source_pixels": [decoded.width, decoded.height],
                        "crop_pixels": [cropped.cgImage?.width ?? 0, cropped.cgImage?.height ?? 0],
                        "ocr_pixels": [prepared.width, prepared.height], "pixel_signature": digest,
                        "samples": samples, "main_actor_harness": true,
                        "process_lifetime_maxrss_before_bytes": before,
                        "process_lifetime_maxrss_after_bytes": after,
                        "epoch": Date.now.timeIntervalSince1970
                    ]
                    records.append(record)
                    print("PFT_RECEIPT_BASELINE \(String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))")
                }
            }
        }
        #expect(records.count == 56)
        let data = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys, .prettyPrinted])
        Attachment.record(data, named: "perf301-simulator-records.json")
    }

    private static func highWaterBytes() -> Int64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        // Darwin reports bytes. This is cumulative process high-water, NOT an interval peak.
        return Int64(usage.ru_maxrss)
    }

    private static func digest(_ image: UIImage) throws -> String {
        let cg = try #require(image.cgImage)
        let data = try #require(cg.dataProvider?.data as Data?)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func syntheticReceipt() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
            UIColor.white.setFill()
            context.fill(CGRect(x: 900, y: 120, width: 2200, height: 2780))
            let lines = ["PERF301 TEST", "DOCUMENTO COMMERCIALE", "16/10/2026", "ARTICOLO TEST   12,34", "TOTALE EUR 12,34"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 1050, y: 350 + index * 400), withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 85, weight: .regular), .foregroundColor: UIColor.black
                ])
            }
        }
    }
}
}
