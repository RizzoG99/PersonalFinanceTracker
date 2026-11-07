// Triage for scenario screenshots: says which ones changed since a baseline and where, so a
// reviewer opens only those. It never decides pass or fail; the scenario assertions do that.
//
// Run it through `scripts/xcb shots-diff [baseline-dir]`. `--self-test` checks the comparison.
//
// A false "changed" costs one extra look. A false "same" hides a bug. So everything here leans
// towards "changed":
// - It reads full-size pixels in colour. A whole-image score such as SSIM averages a one-digit
//   change away, and SSIM on brightness alone misses a colour change of equal brightness.
// - One pixel over `tolerance` is enough to mark its tile.
//
// ponytail: comparing every pixel relies on the same simulator rendering the same way. A
// baseline from another Xcode or OS shows everything as changed; add a perceptual pass then.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let tolerance = 8 // Per colour channel, out of 255.
let tileSize = 16 // Pixels. Changed tiles are grouped into regions.
let mergeGap = 2 // Tiles this close end up in one region.
let padding = 24 // Pixels of context around a crop.
let maxCrops = 5 // Beyond this, or past `wholeShotShare`, the crops stop being cheaper.
let wholeShotShare = 0.5
let cursorMaxWidth = 8 // Pixels. See `cursorBar`.

/// Rows of status bar to skip, in pixels: its clock differs on every run. Fixing it with
/// `simctl status_bar override` instead coincided with a flaky iPad scenario in 2 runs of 2,
/// and 0 of 1 without it, so the harness stays untouched.
/// ponytail: portrait iPhone 17 and iPad Pro 11" only. On another device the clock shows up as
/// a change, or a sliver of content goes unseen; measure the band when the devices change.
func statusBarRows(_ name: String) -> Int {
    name.contains("-ipad-") ? 48 : 128
}

struct Bitmap {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}

struct Region: Codable, Equatable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int
}

struct Finding: Codable {
    let shot: String
    let status: String // new, resized, changed, failure or cursor
    var changedPixels: Int?
    var regions: [Region]?
    var crops: [String]?
}

struct Report: Codable {
    let baseline: String
    let compared: Int
    let toReview: Int
    let review: [Finding]
    let cursorBlinks: [Finding]
    let same: [String]
}

func decode(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Drawing into an sRGB context makes pixels comparable whatever profile the PNG carries.
func bitmap(_ image: CGImage) -> Bitmap? {
    let (width, height) = (image.width, image.height)
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? Bitmap(width: width, height: height, rgba: rgba) : nil
}

func differs(_ a: Bitmap, _ b: Bitmap, _ x: Int, _ y: Int) -> Bool {
    let i = (y * a.width + x) * 4
    return (0 ..< 3).contains { abs(Int(a.rgba[i + $0]) - Int(b.rgba[i + $0])) > tolerance }
}

/// The areas where two same-size bitmaps differ below `skipRows`, and how many pixels differ.
func compare(_ a: Bitmap, _ b: Bitmap, skipRows: Int = 0) -> (regions: [Region], changedPixels: Int) {
    let tilesX = (a.width + tileSize - 1) / tileSize
    let tilesY = (a.height + tileSize - 1) / tileSize
    var marked = [Bool](repeating: false, count: tilesX * tilesY)
    var changedPixels = 0
    for y in min(skipRows, a.height) ..< a.height {
        for x in 0 ..< a.width where differs(a, b, x, y) {
            changedPixels += 1
            marked[(y / tileSize) * tilesX + x / tileSize] = true
        }
    }

    var regions: [Region] = []
    var visited = [Bool](repeating: false, count: marked.count)
    for start in marked.indices where marked[start] && !visited[start] {
        var stack = [start]
        visited[start] = true
        var (minX, minY, maxX, maxY) = (tilesX, tilesY, 0, 0)
        while let tile = stack.popLast() {
            let (tx, ty) = (tile % tilesX, tile / tilesX)
            (minX, minY, maxX, maxY) = (min(minX, tx), min(minY, ty), max(maxX, tx), max(maxY, ty))
            for ny in max(0, ty - mergeGap) ... min(tilesY - 1, ty + mergeGap) {
                for nx in max(0, tx - mergeGap) ... min(tilesX - 1, tx + mergeGap) {
                    let next = ny * tilesX + nx
                    if marked[next], !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
        }
        let (x, y) = (minX * tileSize, minY * tileSize)
        regions.append(Region(
            x: x, y: y,
            w: min((maxX + 1) * tileSize, a.width) - x,
            h: min((maxY + 1) * tileSize, a.height) - y
        ))
    }
    return (regions, changedPixels)
}

/// The exact box of the change when it is one thin, solid, upright bar: a text cursor caught at
/// the other end of its blink, which the harness cannot time. It stays in the report, apart from
/// the shots to review. A cursor that moved leaves two bars, and that still counts as changed.
/// ponytail: anything else shaped like that, say a new divider, passes as a cursor too.
func cursorBar(_ a: Bitmap, _ b: Bitmap, in region: Region, changedPixels: Int) -> Region? {
    var (minX, minY, maxX, maxY) = (Int.max, Int.max, -1, -1)
    for y in region.y ..< region.y + region.h {
        for x in region.x ..< region.x + region.w where differs(a, b, x, y) {
            (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
        }
    }
    let (w, h) = (maxX - minX + 1, maxY - minY + 1)
    guard w <= cursorMaxWidth, h >= w * 4, Double(changedPixels) >= 0.8 * Double(w * h) else { return nil }
    return Region(x: minX, y: minY, w: w, h: h)
}

/// Baseline on the left, current on the right, so one small picture shows the change.
func writeCrop(_ region: Region, before: CGImage, after: CGImage, to url: URL) -> Bool {
    let box = CGRect(x: region.x, y: region.y, width: region.w, height: region.h)
        .insetBy(dx: CGFloat(-padding), dy: CGFloat(-padding))
        .intersection(CGRect(x: 0, y: 0, width: before.width, height: before.height))
    let separator = 8
    let (width, height) = (Int(box.width), Int(box.height))
    guard let left = before.cropping(to: box), let right = after.cropping(to: box),
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: width * 2 + separator, height: height, bitsPerComponent: 8,
              bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return false }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: context.width, height: height))
    context.draw(left, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(right, in: CGRect(x: width + separator, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(file, image, nil)
    return CGImageDestinationFinalize(file)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("shots-diff: \(message)\n".utf8))
    exit(2)
}

func selfTest() {
    func blank(_ edit: (inout [UInt8]) -> Void = { _ in }) -> Bitmap {
        var rgba = [UInt8](repeating: 200, count: 100 * 100 * 4)
        edit(&rgba)
        return Bitmap(width: 100, height: 100, rgba: rgba)
    }
    func set(_ rgba: inout [UInt8], x: Int, y: Int, _ colour: [UInt8]) {
        for (channel, value) in colour.enumerated() {
            rgba[(y * 100 + x) * 4 + channel] = value
        }
    }
    let base = blank()
    assert(compare(base, base).regions.isEmpty, "identical images")

    let onePixel = blank { set(&$0, x: 50, y: 50, [0, 0, 0]) }
    assert(compare(base, onePixel).regions == [Region(x: 48, y: 48, w: 16, h: 16)], "one pixel")

    let faint = blank { set(&$0, x: 50, y: 50, [200 + UInt8(tolerance), 200, 200]) }
    assert(compare(base, faint).regions.isEmpty, "within tolerance")

    // Same brightness (0.299 R + 0.587 G + 0.114 B), different colour.
    let sameLuma = blank { set(&$0, x: 10, y: 10, [230, 185, 200 - 3]) }
    assert(compare(base, sameLuma).changedPixels == 1, "colour change of equal brightness")

    let twoAreas = blank {
        set(&$0, x: 1, y: 1, [0, 0, 0])
        set(&$0, x: 98, y: 98, [0, 0, 0])
    }
    assert(compare(base, twoAreas).regions.count == 2, "far apart areas stay separate")

    let neighbours = blank {
        set(&$0, x: 1, y: 1, [0, 0, 0])
        set(&$0, x: 40, y: 1, [0, 0, 0])
    }
    assert(compare(base, neighbours).regions.count == 1, "nearby areas merge")
    assert(compare(base, onePixel, skipRows: 51).regions.isEmpty, "status bar rows are skipped")
    assert(compare(base, onePixel, skipRows: 50).changedPixels == 1, "the row below them is not")
    assert(statusBarRows("S1-Home-ipad-dark.png") == 48, "iPad status bar")
    assert(statusBarRows("S1-Home-iphone-dark.png") == 128, "iPhone status bar")

    func paint(_ xs: Range<Int>, _ ys: Range<Int>) -> Bitmap {
        blank { rgba in
            for y in ys { for x in xs { set(&rgba, x: x, y: y, [0, 0, 0]) } }
        }
    }
    func bar(_ image: Bitmap) -> Region? {
        let (regions, changedPixels) = compare(base, image)
        return cursorBar(base, image, in: regions[0], changedPixels: changedPixels)
    }
    assert(bar(paint(50 ..< 54, 20 ..< 60)) == Region(x: 50, y: 20, w: 4, h: 40), "a cursor")
    assert(bar(paint(20 ..< 60, 20 ..< 60)) == nil, "a block is not a cursor")
    assert(bar(paint(20 ..< 60, 50 ..< 54)) == nil, "nor is a flat line")
    assert(bar(onePixel) == nil, "nor a dot")
    assert(bar(neighbours) == nil, "nor two dots")
    print("shots-diff self-test passed")
}

let arguments = CommandLine.arguments
if arguments.count == 2, arguments[1] == "--self-test" {
    selfTest()
    exit(0)
}
guard arguments.count == 4 else {
    fail("usage: shots-diff <baseline-dir> <current-dir> <crops-dir> | --self-test")
}

let manager = FileManager.default
let baseline = URL(fileURLWithPath: arguments[1])
let current = URL(fileURLWithPath: arguments[2])
let cropsDir = URL(fileURLWithPath: arguments[3])
guard let names = try? manager.contentsOfDirectory(atPath: current.path).filter({ $0.hasSuffix(".png") }).sorted(),
      !names.isEmpty
else { fail("no screenshots in \(current.path); run scripts/xcb scenarios first") }
guard manager.fileExists(atPath: baseline.path) else {
    fail("no baseline at \(baseline.path); after reviewing a run, save one with scripts/xcb shots-diff --accept")
}
try? manager.removeItem(at: cropsDir)
do {
    try manager.createDirectory(at: cropsDir, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(cropsDir.path): \(error.localizedDescription)")
}

var review: [Finding] = []
var cursorBlinks: [Finding] = []
var same: [String] = []
for name in names {
    // Scenario shots are S<n>-…; anything else is XCTest's picture of a failure, with no baseline.
    guard name.first == "S", name.dropFirst().first?.isNumber == true else {
        review.append(Finding(shot: name, status: "failure"))
        continue
    }
    let oldURL = baseline.appendingPathComponent(name)
    guard manager.fileExists(atPath: oldURL.path) else {
        review.append(Finding(shot: name, status: "new"))
        continue
    }
    guard let before = decode(oldURL), let after = decode(current.appendingPathComponent(name)),
          let a = bitmap(before), let b = bitmap(after)
    else { fail("cannot read \(name)") }
    guard a.width == b.width, a.height == b.height else {
        review.append(Finding(shot: name, status: "resized"))
        continue
    }
    let (regions, changedPixels) = compare(a, b, skipRows: statusBarRows(name))
    if regions.isEmpty {
        same.append(name)
        continue
    }
    if regions.count == 1, let bar = cursorBar(a, b, in: regions[0], changedPixels: changedPixels) {
        cursorBlinks.append(Finding(shot: name, status: "cursor", changedPixels: changedPixels, regions: [bar]))
        continue
    }
    let area = regions.reduce(0) { $0 + $1.w * $1.h }
    var crops: [String]?
    if regions.count <= maxCrops, Double(area) < wholeShotShare * Double(a.width * a.height) {
        crops = regions.enumerated().compactMap { index, region in
            let url = cropsDir.appendingPathComponent("\(name.dropLast(4))-\(index + 1).png")
            return writeCrop(region, before: before, after: after, to: url) ? url.relativePath : nil
        }
    }
    review.append(Finding(shot: name, status: "changed", changedPixels: changedPixels, regions: regions, crops: crops))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let report = Report(
    baseline: arguments[1], compared: names.count, toReview: review.count, review: review,
    cursorBlinks: cursorBlinks, same: same
)
guard let json = try? encoder.encode(report) else { fail("cannot encode the report") }
print(String(decoding: json, as: UTF8.self))
