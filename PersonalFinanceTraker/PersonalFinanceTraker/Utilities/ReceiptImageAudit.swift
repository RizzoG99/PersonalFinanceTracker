import Foundation
import UIKit

/// Content-free, opt-in receipt boundaries. Task-local correlation follows the capture
/// task into the existing OCR task; callback context is restored explicitly by its delegate.
/// This does not move work between actors or claim that a view callback presented a frame.
enum ReceiptImageAudit {
    @TaskLocal static var request = "unattributed"

    static var context: String { "request=\(request)" }

    static func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        try PerformanceAuditRecorder.measure(name, metadata: context, operation)
    }

    static func image(_ name: StaticString, _ image: UIImage) {
        PerformanceAuditRecorder.event(name, metadata:
            "\(context) pixels=\(image.cgImage?.width ?? 0)x\(image.cgImage?.height ?? 0) orientation=\(image.imageOrientation.rawValue) scale=\(image.scale) size=\(image.size.width)x\(image.size.height)")
    }

    static func pixels(_ name: StaticString, _ image: CGImage) {
        PerformanceAuditRecorder.event(name, metadata:
            "\(context) pixels=\(image.width)x\(image.height) bytes_per_row=\(image.bytesPerRow)")
    }

    // Fixture acquisition is a SEPARATE run: disk I/O changes capture latency.
    // Original AVFoundation bytes and the exact already-padded quad used after resumption
    // are saved only in the isolated TEST app, never enabled by ordinary profiling.
    private static var exportsEnabled: Bool {
        PerformanceAuditRecorder.isEnabled
            && Bundle.main.bundleIdentifier == "rizzoG99.PersonalFinanceTraker.test"
            && ProcessInfo.processInfo.arguments.contains("-performanceAuditReceiptFixtures")
    }

    static func exportOriginal(_ data: Data) {
        guard exportsEnabled else { return }
        export("\(request).receiptphoto") { data }
    }

    static func exportQuad(_ quad: [CGPoint]?, image: UIImage) {
        guard exportsEnabled else { return }
        export("\(request).json") {
            let record: [String: Any] = [
                "request": request, "original": "\(request).receiptphoto",
                "quad": quad.map { $0.map { [$0.x, $0.y] } } as Any? ?? NSNull(),
                "quad_already_padded": true,
                "orientation": image.imageOrientation.rawValue,
                "pixel_width": image.cgImage?.width ?? 0,
                "pixel_height": image.cgImage?.height ?? 0
            ]
            return try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
        }
    }

    private static func export(_ filename: String, data: () throws -> Data) {
        let interval = PerformanceAuditRecorder.begin("Receipt.fixture.export", metadata: context)
        var outcome: PerformanceAuditRecorder.Outcome = .failed
        defer { PerformanceAuditRecorder.end(interval, outcome: outcome, metadata: context) }
        do {
            let directory = URL.documentsDirectory.appending(path: "PERF301Fixtures", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data().write(to: directory.appending(path: filename), options: .atomic)
            outcome = .completed
        } catch {
            // No image contents, paths or receipt text in public audit logs.
            PerformanceAuditRecorder.event("Receipt.fixture.exportFailed", metadata: context)
        }
    }
}
