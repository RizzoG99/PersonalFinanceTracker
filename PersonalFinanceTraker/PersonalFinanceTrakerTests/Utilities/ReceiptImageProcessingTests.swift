import Testing
import UIKit
@testable import PersonalFinanceTraker

@Suite(.serialized)
@MainActor
struct ReceiptImageProcessingTests {
    private let full = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1),
                        CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]

    @Test(arguments: [UIImage.Orientation.up, .down, .left, .right,
                      .upMirrored, .downMirrored, .leftMirrored, .rightMirrored])
    func cropPreservesDisplayedOrientation(_ orientation: UIImage.Orientation) throws {
        let original = ReceiptImageTestFixture.colorChart()
        let image = UIImage(cgImage: try #require(original.cgImage), scale: 1, orientation: orientation)
        // Independent display oracle: the content UIImage shows before processing.
        let expected = ReceiptImageTestFixture.displayed(image)
        let actual = ReceiptCameraModel.cropped(image, to: full)
        #expect(actual.imageOrientation == .up)
        #expect(actual.scale == 1)
        #expect(actual.cgImage?.width == Int(image.size.width))
        #expect(actual.cgImage?.height == Int(image.size.height))
        #expect(try ReceiptImageTestFixture.rgba(actual) == ReceiptImageTestFixture.rgba(expected))
    }

    @Test func cropUsesVisionBottomOriginAndDoesNotPadAgain() throws {
        let image = ReceiptImageTestFixture.colorChart()
        // Top left quarter in Vision coordinates: red, not the blue bottom left.
        let quad = [CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 1),
                    CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0.5)]
        let cropped = ReceiptCameraModel.cropped(image, to: quad)
        #expect(cropped.size == CGSize(width: 200, height: 150))
        #expect(try ReceiptImageTestFixture.pixel(cropped, x: 100, y: 75) == [255, 0, 0, 255])
        let input = [CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.8, y: 0.8),
                     CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.2, y: 0.2)]
        let padded = ReceiptCameraModel.padded(input)
        #expect(abs(padded[0].x - 0.155) < 0.000001)
        #expect(abs(padded[0].y - 0.845) < 0.000001)
        let once = ReceiptCameraModel.cropped(image, to: padded)
        #expect(abs(once.size.width - 276) <= 1)
        #expect(abs(once.size.height - 207) <= 1)
    }

    @Test func polygonMasksNeighboursWhiteWithoutDistortingContent() throws {
        let image = ReceiptImageTestFixture.colorChart()
        let diamond = [CGPoint(x: 0.5, y: 1), CGPoint(x: 1, y: 0.5),
                       CGPoint(x: 0.5, y: 0), CGPoint(x: 0, y: 0.5)]
        let cropped = ReceiptCameraModel.cropped(image, to: diamond)
        #expect(cropped.size == image.size)
        #expect(try ReceiptImageTestFixture.pixel(cropped, x: 10, y: 10) == [255, 255, 255, 255])
        #expect(try ReceiptImageTestFixture.pixel(cropped, x: 175, y: 110) == [255, 0, 0, 255])
    }

    @Test(arguments: [0, 1, 2])
    func absentOrImplausiblySmallQuadKeepsOriginal(_ variant: Int) throws {
        let chart = ReceiptImageTestFixture.colorChart()
        let image = UIImage(cgImage: try #require(chart.cgImage), scale: 1, orientation: .right)
        let quads: [[CGPoint]?] = [nil, [], [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.45, y: 0.4),
                                           CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.4, y: 0.45)]]
        let result = ReceiptCameraModel.processedPhoto(image, normalizedQuad: quads[variant])
        #expect(result === image)
    }

    @Test func cropClipsBoundingBoxToFrame() throws {
        let image = ReceiptImageTestFixture.colorChart()
        let quad = [CGPoint(x: -0.2, y: 1.2), CGPoint(x: 1.2, y: 1.2),
                    CGPoint(x: 1.2, y: -0.2), CGPoint(x: -0.2, y: -0.2)]
        let result = ReceiptCameraModel.cropped(image, to: quad)
        #expect(try ReceiptImageTestFixture.rgba(result) == ReceiptImageTestFixture.rgba(image))
        let padded = ReceiptCameraModel.padded(quad)
        #expect(padded.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    @Test(arguments: [UIImage.Orientation.up, .right, .downMirrored])
    func recognitionCapsPixelsWithoutUpscaling(_ orientation: UIImage.Orientation) throws {
        let large = ReceiptImageTestFixture.colorChart(size: CGSize(width: 4032, height: 3024))
        let image = UIImage(cgImage: try #require(large.cgImage), scale: 1, orientation: orientation)
        let prepared = try #require(image.preparedForRecognition())
        #expect(max(prepared.width, prepared.height) == 2000)
        #expect(min(prepared.width, prepared.height) == 1500)
        let small = ReceiptImageTestFixture.colorChart()
        let smallImage = UIImage(cgImage: try #require(small.cgImage), scale: 1, orientation: orientation)
        let smallPrepared = try #require(smallImage.preparedForRecognition())
        #expect(smallPrepared.width == Int(smallImage.size.width))
        #expect(smallPrepared.height == Int(smallImage.size.height))
        let expected = ReceiptImageTestFixture.displayed(smallImage)
        #expect(try ReceiptImageTestFixture.rgba(UIImage(cgImage: smallPrepared)) == ReceiptImageTestFixture.rgba(expected))
    }
}

/// Known coloured regions give geometry assertions independent of OCR or private photos.
@MainActor
enum ReceiptImageTestFixture {
    static func colorChart(size: CGSize = CGSize(width: 400, height: 300)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let half = CGSize(width: size.width / 2, height: size.height / 2)
            for (rect, color) in [
                (CGRect(origin: .zero, size: half), UIColor.red),
                (CGRect(origin: CGPoint(x: half.width, y: 0), size: half), UIColor.green),
                (CGRect(origin: CGPoint(x: 0, y: half.height), size: half), UIColor.blue),
                (CGRect(origin: CGPoint(x: half.width, y: half.height), size: half), UIColor.black)
            ] { color.setFill(); context.fill(rect) }
        }
    }

    static func displayed(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func rgba(_ image: UIImage) throws -> [UInt8] {
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }

    static func pixel(_ image: UIImage, x: Int, y: Int) throws -> [UInt8] {
        let width = try #require(image.cgImage).width
        let bytes = try rgba(image)
        return Array(bytes[((y * width + x) * 4)..<((y * width + x) * 4 + 4)])
    }
}
