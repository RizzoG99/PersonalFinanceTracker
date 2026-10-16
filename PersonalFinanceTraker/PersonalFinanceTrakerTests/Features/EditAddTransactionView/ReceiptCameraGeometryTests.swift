//
//  ReceiptCameraGeometryTests.swift
//  PersonalFinanceTrakerTests
//

import CoreGraphics
import ImageIO
import Testing
@testable import PersonalFinanceTraker

/// The camera itself cannot run in the simulator, so this is the only automated guard on the
/// rotation math behind the receipt outline and crop (#242).
struct ReceiptCameraGeometryTests {
    /// Vision point (0.2, 0.1) is near the screen's bottom-left: x 0.2 from the left, 0.9 down from
    /// the top. Where that lands on the sensor depends on how the preview turns the sensor image.
    @Test(arguments: [
        (CGFloat(0), CGPoint(x: 0.2, y: 0.9)),
        (CGFloat(90), CGPoint(x: 0.9, y: 0.8)),
        (CGFloat(180), CGPoint(x: 0.8, y: 0.1)),
        (CGFloat(270), CGPoint(x: 0.1, y: 0.2)),
    ])
    func sensorPointUndoesThePreviewRotation(angle: CGFloat, expected: CGPoint) {
        let sensor = ReceiptCameraGeometry.sensorPoint(fromVision: CGPoint(x: 0.2, y: 0.1), angle: angle)
        #expect(abs(sensor.x - expected.x) < 1e-9)
        #expect(abs(sensor.y - expected.y) < 1e-9)
    }

    @Test(arguments: [
        (CGFloat(0), CGImagePropertyOrientation.up),
        (CGFloat(90), .right),
        (CGFloat(180), .down),
        (CGFloat(270), .left),
    ])
    func visionOrientationMatchesTheAngle(angle: CGFloat, expected: CGImagePropertyOrientation) {
        #expect(ReceiptCameraGeometry.visionOrientation(for: angle) == expected)
    }
}
