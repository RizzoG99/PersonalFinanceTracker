import CryptoKit
import Foundation
import Testing
import UIKit
@testable import PersonalFinanceTraker

@Suite(.serialized)
@MainActor
struct ReceiptCropParityTests {
    @Test(arguments: [UIImage.Orientation.up, .down, .left, .right,
                      .upMirrored, .downMirrored, .leftMirrored, .rightMirrored])
    func matchesPreChangeRaster(_ orientation: UIImage.Orientation) throws {
        let source = ReceiptImageTestFixture.colorChart(size: CGSize(width: 403, height: 301))
        let pixels = try #require(source.cgImage)
        let cases: [[CGPoint]?] = [nil, [],
            [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)],
            [CGPoint(x: 0.173, y: 0.911), CGPoint(x: 0.827, y: 0.867),
             CGPoint(x: 0.793, y: 0.139), CGPoint(x: 0.211, y: 0.173)],
            [CGPoint(x: -0.1, y: 1.1), CGPoint(x: 1.1, y: 1.1),
             CGPoint(x: 1.1, y: -0.1), CGPoint(x: -0.1, y: -0.1)],
            [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.45, y: 0.4),
             CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.4, y: 0.45)]]
        for scale: CGFloat in [1, 2] {
            let image = UIImage(cgImage: pixels, scale: scale, orientation: orientation)
            for quad in cases {
                let expected = ReceiptCropReference.process(image, quad: quad)
                let actual = ReceiptCameraModel.processedPhoto(image, normalizedQuad: quad)
                #expect(actual.size == expected.size)
                #expect(actual.imageOrientation == expected.imageOrientation)
                #expect(actual.scale == expected.scale)
                #expect(try ReceiptImageTestFixture.rgba(actual) == ReceiptImageTestFixture.rgba(expected))
            }
        }
    }

    @Test(arguments: [UIImage.Orientation.up, .right, .downMirrored])
    func transparentInputsKeepExistingCompositing(_ orientation: UIImage.Orientation) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { c in
            UIColor.red.withAlphaComponent(0.5).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 250, height: 200))
        }
        let image = UIImage(cgImage: try #require(source.cgImage), scale: 1, orientation: orientation)
        let quad = [CGPoint(x: 0.11, y: 0.93), CGPoint(x: 0.89, y: 0.93),
                    CGPoint(x: 0.89, y: 0.07), CGPoint(x: 0.11, y: 0.07)]
        #expect(try ReceiptImageTestFixture.rgba(ReceiptCameraModel.processedPhoto(image, normalizedQuad: quad))
            == ReceiptImageTestFixture.rgba(ReceiptCropReference.process(image, quad: quad)))
    }

}

/// Frozen two-render oracle from pre-experiment camera source SHA-256
/// 0bce45929ad2c2b3e50c78d61c661b97d5419c5b68ff1eb59fafd593aa7e90e2.
/// Test-only: keeps old output observable independently of production refactoring.
@MainActor
enum ReceiptCropReference {
    static func process(_ image: UIImage, quad: [CGPoint]?) -> UIImage {
        guard let quad else { return image }
        let upright: CGImage?
        if image.imageOrientation == .up { upright = image.cgImage }
        else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }.cgImage
        }
        guard let upright else { return image }
        let width = CGFloat(upright.width), height = CGFloat(upright.height)
        let corners = quad.map { CGPoint(x: $0.x * width, y: (1 - $0.y) * height) }
        let box = corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard box.width > width * 0.15, box.height > height * 0.15 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: box.size, format: format).image { c in
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: box.size))
            UIImage(cgImage: upright).draw(at: CGPoint(x: -box.minX, y: -box.minY))
            let mask = UIBezierPath(rect: CGRect(origin: .zero, size: box.size))
            let shape = UIBezierPath()
            shape.move(to: CGPoint(x: corners[0].x - box.minX, y: corners[0].y - box.minY))
            for corner in corners.dropFirst() {
                shape.addLine(to: CGPoint(x: corner.x - box.minX, y: corner.y - box.minY))
            }
            shape.close()
            mask.append(shape)
            mask.usesEvenOddFillRule = true
            UIColor.white.setFill()
            mask.fill()
        }
    }
}

@Suite(.serialized)
@MainActor
struct ReceiptCropFixtureParityTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PFT_RECEIPT_FIXTURES"] == "1"))
    func realPhotosKeepCropAndOCRPixels() throws {
        let urls = ReceiptFixtures.bundle.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? []
        func file(_ name: String) throws -> URL {
            try #require(urls.first { $0.lastPathComponent == name }, "Missing private fixture: \(name)")
        }
        let expected = try JSONDecoder().decode([PerformanceRecorderSerialTests.ReceiptImageDeviceFixtureTests.Expected].self,
            from: Data(contentsOf: file("perf301-expectations.json")))
        try #require(!expected.isEmpty)
        var records: [[String: Any]] = []
        for item in expected {
            try autoreleasepool {
                let capture = try JSONDecoder().decode(PerformanceRecorderSerialTests.ReceiptImageDeviceFixtureTests.Capture.self,
                    from: Data(contentsOf: file("\(item.id).json")))
                let image = try #require(UIImage(data: Data(contentsOf: file(capture.original))))
                let quad = capture.quad?.map { CGPoint(x: $0[0], y: $0[1]) }
                let before = ReceiptCropReference.process(image, quad: quad)
                let after = ReceiptCameraModel.processedPhoto(image, normalizedQuad: quad)
                let beforeBytes = try ReceiptImageTestFixture.rgba(before)
                let afterBytes = try ReceiptImageTestFixture.rgba(after)
                let cropParity = beforeBytes == afterBytes
                #expect(before.size == after.size)
                #expect(cropParity, "Crop pixels changed: \(item.id)")
                if !cropParity {
                    Attachment.record(try #require(before.pngData()), named: "\(item.id)-reference.png")
                    Attachment.record(try #require(after.pngData()), named: "\(item.id)-candidate.png")
                }
                let beforeOCR = try #require(before.preparedForRecognition())
                let afterOCR = try #require(after.preparedForRecognition())
                let ocrParity = try ReceiptImageTestFixture.rgba(UIImage(cgImage: beforeOCR))
                    == ReceiptImageTestFixture.rgba(UIImage(cgImage: afterOCR))
                #expect(beforeOCR.width == afterOCR.width && beforeOCR.height == afterOCR.height)
                #expect(ocrParity, "OCR input pixels changed: \(item.id)")
                records.append(["id": item.id, "crop_parity": cropParity, "ocr_parity": ocrParity,
                    "crop_pixels": [after.cgImage?.width ?? 0, after.cgImage?.height ?? 0],
                    "ocr_pixels": [afterOCR.width, afterOCR.height],
                    "source_bits_per_component": image.cgImage?.bitsPerComponent ?? 0,
                    "source_alpha_info": image.cgImage?.alphaInfo.rawValue ?? 0,
                    "different_crop_channels": zip(beforeBytes, afterBytes).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) },
                    "crop_rgba_sha256": SHA256.hash(data: Data(afterBytes)).map { String(format: "%02x", $0) }.joined()])
            }
        }
        Attachment.record(try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]),
                          named: "perf301-real-photo-pixel-parity.json")
    }
}
