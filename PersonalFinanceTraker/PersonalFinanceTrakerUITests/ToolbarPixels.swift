//
//  ToolbarPixels.swift
//  PersonalFinanceTrakerUITests
//
//  Toolbar icon colour, measured from pixels (#257, #408). "Ink" is the 3 % of a button's
//  pixels that differ most from its top-left corner (its background). Chroma, max − min of
//  R, G, B, tells a neutral glyph from a coloured one; "indigo" means blue well above red
//  and green.
//

import XCTest

extension ScenarioTestCase {

    struct Target {
        let element: XCUIElement
        let crop: CGRect
    }

    func whole(_ element: XCUIElement) -> Target {
        Target(element: element, crop: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Assertions

    /// Every glyph is neutral, stands out from its background, and matches the others' shade.
    @MainActor
    func assertSameNeutral(_ targets: [(String, Target)]) throws {
        var shades: [(String, Double)] = []
        for (name, target) in targets {
            let ink = try settled { try self.ink(target.element, crop: target.crop) }
            XCTAssertLessThan(ink.chroma, 0.15, "\(name) should draw neutral, ink \(ink)")
            XCTAssertGreaterThan(abs(ink.luminance - ink.background.luminance), 0.4, "\(name) should stand out from its background, ink \(ink)")
            shades.append((name, ink.luminance))
        }
        let spread = shades.map(\.1).max()! - shades.map(\.1).min()!
        XCTAssertLessThan(spread, 0.15, "icons should share one shade: \(shades)")
    }

    /// A filled indigo button with a white glyph: indigo covers most of the button, and the
    /// centre, where the + strokes cross, holds near-white neutral pixels.
    @MainActor
    func assertProminent(_ element: XCUIElement) throws {
        let fill = try settled { try self.indigoShare(element) }
        XCTAssertGreaterThan(fill, 0.4, "+ should be a filled indigo button, indigo share \(fill)")
        let centre = try rgb(element, crop: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3))
        let white = Double(centre.filter { $0.luminance > 0.85 && $0.chroma < 0.1 }.count) / Double(centre.count)
        XCTAssertGreaterThan(white, 0.05, "+ glyph should be white, white share of the centre \(white)")
    }

    // MARK: - Pixels

    struct Pixel: CustomStringConvertible {
        let r, g, b: Double
        var chroma: Double { max(r, g, b) - min(r, g, b) }
        var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
        var isIndigo: Bool { b - max(r, g) > 0.3 }
        var description: String { String(format: "rgb(%.2f, %.2f, %.2f)", r, g, b) }
        func distance(to other: Pixel) -> Double { abs(r - other.r) + abs(g - other.g) + abs(b - other.b) }
    }

    struct Ink: CustomStringConvertible {
        let colour: Pixel
        let background: Pixel
        var chroma: Double { colour.chroma }
        var luminance: Double { colour.luminance }
        var isIndigo: Bool { colour.isIndigo }
        var description: String { "\(colour) on \(background)" }
    }

    /// Reads until two samples agree, because toolbar items fade in after the screen appears.
    @MainActor
    func settled<T>(_ read: @escaping () throws -> T) throws -> T where T: CustomStringConvertible {
        var samples = [try read()]
        let stable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let value = try? read() else { return false }
                defer { samples.append(value) }
                return value.description == samples[samples.count - 1].description
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter().wait(for: [stable], timeout: 10), .completed, "never settled: \(samples)")
        return samples[samples.count - 1]
    }

    @MainActor
    func ink(_ element: XCUIElement, crop: CGRect) throws -> Ink {
        let pixels = try rgb(element, crop: crop)
        let background = pixels[0]
        let ranked = pixels.sorted { $0.distance(to: background) > $1.distance(to: background) }
        let ink = ranked.prefix(max(1, ranked.count * 3 / 100))
        let count = Double(ink.count)
        let mean = Pixel(
            r: ink.reduce(0) { $0 + $1.r } / count,
            g: ink.reduce(0) { $0 + $1.g } / count,
            b: ink.reduce(0) { $0 + $1.b } / count
        )
        return Ink(colour: mean, background: background)
    }

    @MainActor
    func indigoShare(_ element: XCUIElement, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> Double {
        let pixels = try rgb(element, crop: crop)
        return (Double(pixels.filter(\.isIndigo).count) / Double(pixels.count) * 100).rounded() / 100
    }

    /// Pixels of the element's screenshot, cropped to a unit rect; the first is the crop's top-left corner.
    @MainActor
    func rgb(_ element: XCUIElement, crop: CGRect) throws -> [Pixel] {
        let full = try XCTUnwrap(element.screenshot().image.cgImage)
        let rect = CGRect(
            x: crop.minX * CGFloat(full.width), y: crop.minY * CGFloat(full.height),
            width: crop.width * CGFloat(full.width), height: crop.height * CGFloat(full.height)
        ).integral
        let image = try XCTUnwrap(full.cropping(to: rect))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { i in
            Pixel(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
        }
    }
}
