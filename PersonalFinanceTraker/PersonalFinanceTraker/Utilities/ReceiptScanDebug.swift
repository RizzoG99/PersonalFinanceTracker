//
//  ReceiptScanDebug.swift
//  PersonalFinanceTraker
//
//  Tracing for one question: when a scan reports the *previous* receipt's amount, is it reading a
//  stale image, or reading a fresh image badly?
//
//  Reasoning alone cannot answer that — every scan builds a fresh `ReceiptDocument`, so the code
//  reads as if a leak were impossible, and yet the amount came back wrong. The decisive evidence is
//  a fingerprint of the actual pixels handed to Vision: if scan #4's fingerprint equals scan #3's,
//  the photo is stale and the parser is innocent. If it differs and the total is still the old one,
//  the fault is downstream and the image is innocent.
//
//  ponytail: `print`, not `os.Logger`, matching the existing "found no total" dump this sits beside
//  — the audience is a developer with Xcode open, and it compiles to nothing in release.
//

import Foundation
import UIKit

enum ReceiptScanDebug {
    /// Increments per scan so interleaved async work can be told apart in the log.
    @MainActor private(set) static var scanNumber = 0

    @MainActor static func beginScan(_ source: String) {
        scanNumber += 1
        log("--- begin, source: \(source)")
    }

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[receipt-scan] \(message())")
        #endif
    }

    @MainActor static func log(step: String, _ message: @autoclosure () -> String) {
        log("#\(scanNumber) \(step): \(message())")
    }

    /// A short hash of the image's actual pixel data.
    ///
    /// Content, deliberately, not object identity: two `UIImage`s wrapping the same stale buffer are
    /// different objects, so identity would report "fresh" for exactly the bug being hunted.
    /// Sampled rather than hashed whole — a 12MP buffer is 48MB and this runs on the main thread.
    static func fingerprint(_ image: UIImage?) -> String {
        guard let image, let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data as Data? , !data.isEmpty
        else { return "none" }

        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let step = Swift.max(1, data.count / 512)
        for index in Swift.stride(from: 0, to: data.count, by: step) {
            hash = (hash ^ UInt64(data[index])) &* 0x100_0000_01b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    static func describe(_ image: UIImage?) -> String {
        guard let image else { return "nil" }
        let pixels = image.cgImage.map { "\($0.width)x\($0.height)" } ?? "?"
        return "\(pixels) orient=\(image.imageOrientation.rawValue) fp=\(fingerprint(image))"
    }
}
