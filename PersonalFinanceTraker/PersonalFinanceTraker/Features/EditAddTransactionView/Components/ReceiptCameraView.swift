//
//  ReceiptCameraView.swift
//  PersonalFinanceTraker
//
//  A point-and-shoot viewfinder for receipt capture, replacing VNDocumentCameraViewController.
//
//  VisionKit's scanner is built for *documents you keep*: it waits to agree on the page edges, lets
//  you drag the corners, then offers more pages and a review screen before it hands anything back.
//  Every one of those steps is fixed — the class takes no configuration at all — and none of them
//  earns its cost here, because `ReceiptParser` reads recognized text lines and their bounding
//  boxes. It never needed a hand-cropped, rectified page. So the user was paying for a cropping
//  workflow whose output we throw away.
//
//  This is one tap: aim, shoot, done. What VisionKit did usefully — straightening a receipt shot at
//  an angle — still happens, but automatically and after the shutter, in `ReceiptTextRecognizer`,
//  where a failed detection costs nothing because the full frame is a fine fallback.
//
//  Deliberately absent, all of them things the old scanner did: multi-page capture, manual corner
//  editing, and a review step. See the type-level note on `ReceiptCameraModel` for the torch, which
//  is the one control worth keeping.
//

import AVFoundation
import AVKit
import SwiftUI
import UIKit
import Vision

struct ReceiptCameraView: View {
    /// Empty means the user backed out — the caller leaves the form untouched.
    var onFinish: (Result<[UIImage], Error>) -> Void

    @State private var model = ReceiptCameraModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Black rather than an app token on purpose: a viewfinder is its own platform idiom and
            // should read like the system Camera app, exactly as VisionKit's full-screen scanner did.
            Color.black.ignoresSafeArea()

            if model.isAuthorized {
                CameraPreview(session: model.session) { model.attach(previewLayer: $0) }
                    // Inside the preview's own bounds on purpose: the quad arrives already
                    // converted to preview-layer coordinates, so any other space would offset it by
                    // the safe-area inset.
                    .overlay { receiptOutline }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25),
                               value: model.detectedQuad == nil)
                    .ignoresSafeArea()
            } else {
                // The permission alert lives at the call site, which checks access *before*
                // presenting this view. Reaching here means access was revoked mid-flight.
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera.fill",
                    description: Text("Allow camera access in Settings, or choose a photo from your library instead.")
                )
                .foregroundStyle(.white)
            }

            controls
        }
        // No `.preferredColorScheme(.dark)` and no `.statusBarHidden()`. Both propagate a preference
        // out of the presented cover and back into the presenting view's environment, which is a
        // known way to get "AttributeGraph: cycle detected" — observed here on the simulator. The
        // view paints its own black ground and white controls, so neither bought anything.
        .task { await model.start() }
        .onDisappear { model.stop() }
        // Volume buttons (and any other hardware capture button) fire the shutter, same as the
        // system Camera app. `.ended` only: `.began` would shoot on press-down, so a long press
        // would fire twice.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { capture() }
        }
    }

    /// The live outline. Purely informational — it never gates the shutter, and nothing about the
    /// capture or the parse depends on it, so a missed or wobbly detection costs the user nothing.
    @ViewBuilder
    private var receiptOutline: some View {
        if let quad = model.detectedQuad {
            ReceiptQuad(corners: quad)
                .stroke(Color.accentIndigo, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                .shadow(color: .black.opacity(0.4), radius: 2)
                // Tuned to the detector, not to taste: corners arrive every ~200ms, so an
                // interpolation of about that long hands over to the next one just as it lands and
                // the edge appears to move continuously. Much shorter and it snaps between
                // positions; much longer and the outline visibly trails the receipt.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: quad)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true) // the state is announced by the caption text instead
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Cancel") { finish(with: []) }
                    .font(.headline)
                Spacer()
                Button {
                    model.toggleTorch()
                } label: {
                    Label(
                        model.isTorchOn ? "Turn Off Light" : "Turn On Light",
                        systemImage: model.isTorchOn ? "bolt.fill" : "bolt.slash.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                }
                // A toggle, so VoiceOver announces on/off rather than the user inferring it from
                // which glyph is showing.
                .accessibilityAddTraits(model.isTorchOn ? [.isSelected] : [])
                .disabled(!model.hasTorch)
            }
            .padding(.horizontal)

            Spacer()

            // Guidance, not decoration: this replaces the reassurance VisionKit's own "hold still,
            // detecting" state used to give. Keep it short — it sits over a live image.
            //
            // It also carries the detection state in *text*. The outline alone communicates through
            // shape and colour only, which VoiceOver cannot read and Differentiate Without Color
            // users may not see.
            Text(model.detectedQuad == nil
                 ? "Fit the whole receipt in the frame"
                 : "Receipt detected")
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)

            Button {
                capture()
            } label: {
                // The system shutter: a white disc inside a ring. Sized well past the 44pt minimum
                // because it is the one thing on screen the user is aiming to press one-handed.
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
                .opacity(model.isCapturing ? 0.4 : 1)
            }
            .accessibilityLabel("Capture receipt")
            .disabled(model.isCapturing || !model.isAuthorized)
            .padding(.bottom, 32)
        }
        .tint(.white)
        .foregroundStyle(.white)
    }

    private func capture() {
        // The shutter button is disabled while capturing; a hardware button is not, so a second
        // press would otherwise land on the model's own guard and report a bogus failure.
        guard !model.isCapturing, model.isAuthorized else { return }
        Task {
            guard let image = await model.capture() else {
                finish(with: .failure(ReceiptCameraError.captureFailed))
                return
            }
            finish(with: [image])
        }
    }

    private func finish(with images: [UIImage]) { finish(with: .success(images)) }

    private func finish(with result: Result<[UIImage], Error>) {
        model.stop()
        onFinish(result)
    }
}

enum ReceiptCameraError: Error {
    case captureFailed
}

/// Owns the capture session. `@MainActor` because the view reads its state directly; the session's
/// own blocking work (`startRunning`, configuration) is pushed off the main thread, since both stall
/// for long enough to drop frames on the first appearance.
///
/// The torch is the one control carried over from a request for "flash on by default". It is a
/// *torch*, not a flash, because the problem it solves is framing in the dark — a flash fires after
/// the user has already struggled to aim. It defaults off (blinding in a lit restaurant) but the
/// choice is remembered, so a user who scans receipts in dim places turns it on once.
@MainActor
@Observable
final class ReceiptCameraModel {
    @ObservationIgnored
    let session = AVCaptureSession()
    private(set) var isAuthorized = false
    private(set) var isCapturing = false
    private(set) var hasTorch = false
    /// The detected receipt's corners, already in preview-layer coordinates, or nil when nothing
    /// document-shaped has been in frame for a moment.
    private(set) var detectedQuad: Quad?

    /// Consecutive frames with no detection. The outline is not dropped on the first miss: the
    /// detector fails intermittently on a hand-held shot — a blur, a shadow, a moment of tilt — and
    /// clearing immediately makes the outline strobe on and off while the receipt is plainly still
    /// there. Three misses is ~0.6s at the sampling rate.
    @ObservationIgnored
    private var missedFrames = 0

    /// The same detection in Vision's normalized space, which is what the captured photo needs.
    /// `detectedQuad` is in preview-layer coordinates and cannot be used for cropping — the preview
    /// is `.resizeAspectFill`, so it shows less than the sensor captured.
    @ObservationIgnored
    private var normalizedQuad: [CGPoint]?
    var isTorchOn = false

    @ObservationIgnored
    private let output = AVCapturePhotoOutput()
    @ObservationIgnored
    private var device: AVCaptureDevice?
    @ObservationIgnored
    private var captureDelegate: PhotoCaptureDelegate?
    @ObservationIgnored
    private var isConfigured = false
    @ObservationIgnored
    private var subjectAreaTask: Task<Void, Never>?
    @ObservationIgnored
    private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored
    private var frameDelegate: FrameDelegate?
    @ObservationIgnored
    private let frameQueue = DispatchQueue(label: "receipt.camera.frames")
    /// Apple's rule for `AVCaptureSession`: configuration and `startRunning`/`stopRunning` are
    /// blocking calls, and they belong on one serial queue of your own — never the main one.
    ///
    /// Breaking it is invisible on a device and near-fatal on the simulator, which has no camera:
    /// the fake session fails immediately with -12782, and *every* graph rebuild after that sits
    /// out a nine-second timeout on whatever thread asked for it. Three of those landing on the
    /// main thread froze the app on its splash screen for half a minute.
    @ObservationIgnored
    private let sessionQueue = DispatchQueue(label: "receipt.camera.session")
    /// Weak: the layer belongs to the view, which outlives nothing here and is torn down first.
    @ObservationIgnored
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    /// Plain `UserDefaults`, not `@AppStorage` — that is a `DynamicProperty` built for a `View`'s
    /// update cycle and does not belong in a model object.
    private static let torchDefaultsKey = "receiptScannerTorchOn"
    private var torchPreference: Bool {
        get { UserDefaults.standard.bool(forKey: Self.torchDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.torchDefaultsKey) }
    }

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
    }

    func start() async {
        isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        guard isAuthorized else { return }
        if !isConfigured {
            isConfigured = true
            let delegate = FrameDelegate { [weak self] quad in
                Task { @MainActor in self?.updateQuad(quad) }
            }
            frameDelegate = delegate
            device = await configure(frameDelegate: delegate)
            hasTorch = device?.hasTorch ?? false
        }
        await onSessionQueue { [session] in session.startRunning() }

        // *After* startRunning, deliberately. Device focus/exposure set inside the
        // beginConfiguration/commitConfiguration transaction is applied to a session that is not
        // yet streaming, and the running session re-establishes its own defaults over the top — so
        // the continuous mode set at configure time was silently not the mode in effect.
        configureFocus()

        // "Continuous" in AVFoundation means the lens re-focuses when the *scene* changes, and it
        // only knows the scene changed if subject-area monitoring is on. Without this the camera
        // locks focus on whatever it saw first and holds it while the user moves the receipt —
        // which is exactly the walking-around case this camera exists for.
        subjectAreaTask = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: AVCaptureDevice.subjectAreaDidChangeNotification
            )
            for await _ in changes {
                self?.configureFocus()
            }
        }

        if torchPreference { setTorch(on: true) }
    }

    func stop() {
        subjectAreaTask?.cancel()
        subjectAreaTask = nil
        detectedQuad = nil
        normalizedQuad = nil
        missedFrames = 0
        // Talks to the hardware directly rather than going through `setTorch`, which would publish
        // an `isTorchOn` change from inside `onDisappear` — a mutation during the dismissal update.
        // Never leave the light burning behind a dismissed screen.
        if let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
            device.torchMode = .off
            device.unlockForConfiguration()
        }
        stopSession()
    }

    func toggleTorch() {
        setTorch(on: !isTorchOn)
        torchPreference = isTorchOn
    }

    func capture() async -> UIImage? {
        guard !isCapturing, session.isRunning else { return nil }
        isCapturing = true
        defer { isCapturing = false; captureDelegate = nil }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off // The torch already covers low light, and continuously.
        let photo = await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate { continuation.resume(returning: $0) }
            // AVFoundation holds its delegate weakly, so the only strong reference is this one;
            // without it the callback never arrives and the continuation leaks.
            captureDelegate = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
        guard let photo else {
            ReceiptScanDebug.log("capture: photo output returned nil")
            return nil
        }
        ReceiptScanDebug.log("capture: shutter -> \(ReceiptScanDebug.describe(photo))")
        guard let quad = normalizedQuad else {
            ReceiptScanDebug.log("capture: no outline, using full frame")
            return photo
        }
        let result = Self.cropped(photo, to: quad)
        ReceiptScanDebug.log("capture: cropped -> \(ReceiptScanDebug.describe(result))")
        return result
    }

    /// Trims the photo to the receipt that was outlined on screen.
    ///
    /// Cropping to a detected shape was tried once before, inside `ReceiptTextRecognizer`, and had
    /// to be removed: a confident-but-wrong quad cut the price column off a receipt and the total
    /// came back nil with nothing to warn anyone. What makes it safe here is that the user watched
    /// the outline sit on the receipt before pressing the shutter — the crop is something they
    /// chose, not something done behind their back — and that nothing is ever *distorted*, only
    /// masked.
    ///
    /// Two separate jobs, and an earlier version doing only the first got both wrong:
    ///
    ///  - **Exclude the neighbours.** A second receipt on the same table is read as a second total,
    ///    and the parser either picks the wrong one or asks the user to choose (device report,
    ///    2026-08-29: a €5 gelato reported as the €20.05 fuel receipt beside it). Cropping to the
    ///    quad's *bounding box* does not achieve this — the box of a rotated quad reaches well past
    ///    the paper at each corner, which on that same table pulled the neighbouring receipt back
    ///    in. So everything outside the quad is painted white; the box is only used to avoid
    ///    carrying a mostly-empty frame into OCR.
    ///  - **Keep the whole receipt.** Real receipts curl, so the printed area bows outside the flat
    ///    quad the segmentation returns. That padding is applied where the outline is built, not
    ///    here, so the shape drawn on screen is the shape kept.
    private static func cropped(_ image: UIImage, to quad: [CGPoint]) -> UIImage {
        // Orientation must be baked into the pixels first: Core Graphics knows nothing about
        // `imageOrientation`, so on a portrait photo it would mask a sideways region.
        guard let upright = image.uprightPixels() else { return image }
        let width = CGFloat(upright.width)
        let height = CGFloat(upright.height)

        // Vision counts y upward from the bottom; image rows run downward from the top.
        let corners = quad.map { CGPoint(x: $0.x * width, y: (1 - $0.y) * height) }
        // Already padded by `padded(_:)` when the outline was drawn — deliberately not padded again
        // here, or the region kept would quietly be larger than the one the user was shown.
        let expanded = corners

        let box = expanded
            .reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        // An implausibly small box means the detection was junk; the full frame is the safer answer.
        guard box.width > width * 0.15, box.height > height * 0.15 else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // Never the device scale — see `uprightPixels`.
        format.opaque = true
        return UIGraphicsImageRenderer(size: box.size, format: format).image { context in
            // White, not black: OCR expects dark ink on light paper, and a black surround next to
            // white paper is a hard edge the recognizer can mistake for content.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: box.size))
            UIImage(cgImage: upright).draw(at: CGPoint(x: -box.minX, y: -box.minY))

            // Even-odd fill of "the whole box, minus the quad" paints only the area outside it.
            let mask = UIBezierPath(rect: CGRect(origin: .zero, size: box.size))
            let shape = UIBezierPath()
            shape.move(to: expanded[0].offsetBy(-box.origin.x, -box.origin.y))
            for corner in expanded.dropFirst() {
                shape.addLine(to: corner.offsetBy(-box.origin.x, -box.origin.y))
            }
            shape.close()
            mask.append(shape)
            mask.usesEvenOddFillRule = true
            UIColor.white.setFill()
            mask.fill()
        }
    }

    /// How far the detected quad is pushed out from its centre. Receipts curl, so the segmentation
    /// traces the paper it can see rather than the text near the fold — on a real photo the detected
    /// edge ran straight through the "Totale" column. Including a strip of tablecloth costs nothing;
    /// clipping one digit off the total costs the whole scan.
    private static let quadPadding: CGFloat = 1.15

    /// Grows a normalized quad about its own centre, clamped to the frame.
    ///
    /// Applied once, here, so the outline the user sees and the region the shutter keeps are the
    /// same shape by construction rather than by two constants agreeing.
    private static func padded(_ quad: [CGPoint]) -> [CGPoint] {
        let centre = CGPoint(
            x: quad.map(\.x).reduce(0, +) / CGFloat(quad.count),
            y: quad.map(\.y).reduce(0, +) / CGFloat(quad.count)
        )
        return quad.map { corner in
            CGPoint(
                x: min(max(centre.x + (corner.x - centre.x) * quadPadding, 0), 1),
                y: min(max(centre.y + (corner.y - centre.y) * quadPadding, 0), 1)
            )
        }
    }

    /// Fire-and-forget counterpart to `onSessionQueue`, for a teardown nobody waits on.
    private nonisolated func stopSession() {
        sessionQueue.async { [session] in session.stopRunning() }
    }

    /// Runs blocking session work on `sessionQueue` and suspends until it is done.
    private nonisolated func onSessionQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// Returns the capture device rather than assigning it, so nothing here touches main-actor
    /// state from the session queue.
    private nonisolated func configure(frameDelegate: FrameDelegate) async -> AVCaptureDevice? {
        await onSessionQueue { [session, output, videoOutput, frameQueue] in
            session.beginConfiguration()
            session.sessionPreset = .photo
            // Wide angle only. The ultra-wide and telephoto lenses of a `.builtInDualCamera` virtual
            // device switch by subject distance, and a receipt held close is exactly the range where
            // that switch happens mid-aim.
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) { session.addOutput(output) }

            // A second, cheap output purely to drive the on-screen outline. Late frames are discarded
            // rather than queued: falling behind the live feed would draw the outline where the receipt
            // *was*, which is worse than not drawing it.
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(frameDelegate, queue: frameQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            session.commitConfiguration()
            return device
        }
    }

    /// Converts Vision's normalized corners into points the outline can be drawn with.
    ///
    /// The subtlety that got this wrong first time: `layerPointConverted(fromCaptureDevicePoint:)`
    /// takes **sensor** coordinates, which are fixed landscape (top-left origin, x along the
    /// sensor's long axis) and do *not* rotate with the interface — the same space
    /// `captureDevicePointOfInterest` is documented in. Vision, meanwhile, was handed the buffer as
    /// `.right`, so it answers in the upright portrait space the user is looking at, with a
    /// bottom-left origin. Feeding one to the other drew the quad rotated a quarter turn.
    ///
    /// Derivation, all normalized. Displaying the sensor frame in portrait rotates it 90° clockwise,
    /// so a sensor point (sx, sy) lands at display (1 - sy, sx). Vision's (vx, vy) is that display
    /// point with the y axis flipped: display = (vx, 1 - vy). Inverting the rotation gives
    /// sx = 1 - vy and sy = 1 - vx.
    ///
    /// The layer conversion then accounts for `.resizeAspectFill` showing only part of the frame,
    /// which is why this goes through the layer at all rather than scaling by the view's size.
    private func updateQuad(_ normalized: [CGPoint]?) {
        guard let normalized, normalized.count == 4, let layer = previewLayer else {
            missedFrames += 1
            if missedFrames >= 3 {
                detectedQuad = nil
                normalizedQuad = nil
            }
            return
        }
        let padded = Self.padded(normalized)
        let points = padded.map { corner in
            let sensorPoint = CGPoint(x: 1 - corner.y, y: 1 - corner.x)
            return layer.layerPointConverted(fromCaptureDevicePoint: sensorPoint)
        }
        let measured = Quad(
            topLeft: points[0], topRight: points[1],
            bottomRight: points[2], bottomLeft: points[3]
        )
        missedFrames = 0
        normalizedQuad = padded
        // Eased toward the new reading rather than snapped to it. Segmentation jitters by a few
        // points between frames even on a still receipt, and that jitter reads as a nervous,
        // twitching outline; blending damps it without adding noticeable lag, because the view
        // animation is already carrying the corner from one reading to the next.
        detectedQuad = detectedQuad.map { $0.blended(towards: measured, amount: 0.5) } ?? measured
    }

    /// Continuous autofocus, biased to near subjects — a receipt is held at arm's length or closer,
    /// and the unrestricted range lets the lens hunt past it to the table behind.
    ///
    /// Exposure and white balance go continuous too: a receipt is white paper that fills a varying
    /// share of the frame, so a locked exposure blows out the print as the user moves in.
    ///
    /// Smooth autofocus is deliberately *off*. It exists to keep focus transitions unobtrusive
    /// during video recording by ramping them slowly; for a one-tap still capture that only makes
    /// the camera slower to settle, which is the complaint this whole screen was built to fix.
    private func configureFocus() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
        if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = false }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    private func setTorch(on: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        device.torchMode = on ? .on : .off
        isTorchOn = on
    }
}

/// The detected quadrilateral, as an animatable `Shape` so its corners interpolate between
/// detections instead of the outline cutting from one position to the next.
///
/// `animatableData` is the eight coordinates nested into `AnimatablePair`s — ungainly, but it is
/// what lets SwiftUI move each corner independently. Nothing simpler works: `Path` is not
/// animatable, and `[CGPoint]` does not conform to `VectorArithmetic`.
private struct ReceiptQuad: Shape {
    var corners: Quad

    var animatableData: Quad.AnimatableData {
        get { corners.animatableData }
        set { corners.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: corners.topLeft)
            path.addLine(to: corners.topRight)
            path.addLine(to: corners.bottomRight)
            path.addLine(to: corners.bottomLeft)
            path.closeSubpath()
        }
    }
}

/// Four corners in view coordinates, in drawing order.
struct Quad: Equatable, Animatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    typealias AnimatableData = AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    >

    /// Linear blend towards another quad, corner by corner. `amount` of 1 adopts the new reading
    /// outright; 0.5 halves the frame-to-frame jitter.
    func blended(towards other: Quad, amount: CGFloat) -> Quad {
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
        }
        return Quad(
            topLeft: lerp(topLeft, other.topLeft),
            topRight: lerp(topRight, other.topRight),
            bottomRight: lerp(bottomRight, other.bottomRight),
            bottomLeft: lerp(bottomLeft, other.bottomLeft)
        )
    }

    var animatableData: AnimatableData {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(topLeft.x, topLeft.y),
                               AnimatablePair(topRight.x, topRight.y)),
                AnimatablePair(AnimatablePair(bottomRight.x, bottomRight.y),
                               AnimatablePair(bottomLeft.x, bottomLeft.y))
            )
        }
        set {
            topLeft = CGPoint(x: newValue.first.first.first, y: newValue.first.first.second)
            topRight = CGPoint(x: newValue.first.second.first, y: newValue.first.second.second)
            bottomRight = CGPoint(x: newValue.second.first.first, y: newValue.second.first.second)
            bottomLeft = CGPoint(x: newValue.second.second.first, y: newValue.second.second.second)
        }
    }
}

/// Runs document segmentation over the live feed to drive the outline.
///
/// Deliberately the same detector that was *removed* from `ReceiptTextRecognizer`, where it cropped
/// away the price column on a confident-but-wrong quad. The difference is consequence: here nothing
/// downstream consumes the result, so a bad quad draws a bad outline for a fraction of a second and
/// the parse is untouched. It informs the user's aim; it never decides what gets read.
private final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onQuad: @Sendable ([CGPoint]?) -> Void
    /// Only ever touched on the single sample-buffer queue this delegate is installed on, which is
    /// why `@unchecked Sendable` is honest here rather than a silencer.
    private var lastRun = Date.distantPast

    init(onQuad: @escaping @Sendable ([CGPoint]?) -> Void) {
        self.onQuad = onQuad
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // ~5 detections a second. The feed delivers 30; segmentation on every frame would burn
        // battery to redraw an outline no one can see move that fast.
        let now = Date()
        guard now.timeIntervalSince(lastRun) > 0.2 else { return }
        lastRun = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectDocumentSegmentationRequest()
        // `.right` because the back camera delivers landscape buffers while the UI is portrait;
        // without it the quad comes back rotated a quarter turn from what is on screen.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])

        guard let observation = request.results?.first, observation.confidence > 0.6 else {
            onQuad(nil)
            return
        }
        onQuad([observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft])
    }
}

private extension CGPoint {
    func offsetBy(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}

private extension UIImage {
    /// Redraws so the pixel buffer itself is upright. Scale is pinned to 1: the renderer's default
    /// is the *device* scale, and a camera image already reports its size in pixels, which is how a
    /// 4032x3024 frame once became a 440MB bitmap and got the app killed.
    func uprightPixels() -> CGImage? {
        guard imageOrientation != .up else { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private let completion: @Sendable (UIImage?) -> Void

    init(completion: @escaping @Sendable (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil)
            return
        }
        completion(UIImage(data: data))
    }
}

/// The live feed. `AVCaptureVideoPreviewLayer` has no SwiftUI equivalent, so this is the one place
/// UIKit is unavoidable — a view that is *only* the layer, with no logic of its own.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Handing the layer out is what makes the outline correct: `layerPointConverted` accounts for
    /// `.resizeAspectFill` cropping the feed, which hand-rolled normalized-to-view arithmetic does
    /// not — it would draw the quad offset by however much of the frame is off-screen.
    var onLayer: (AVCaptureVideoPreviewLayer) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        onLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#Preview {
    // No camera in the simulator or in previews, so this renders the unavailable state. The live
    // viewfinder can only be verified on a device.
    ReceiptCameraView { _ in }
}
