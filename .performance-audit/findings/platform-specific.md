# WS-RUNTIME — iOS Platform-Specific Performance

## Scope and method

Static screening covered AVFoundation session ownership/configuration, preview and photo delegates, Vision live segmentation, still-image crop/rendering, Core Image enhancement, and Vision document recognition. Three findings were accepted. Existing mitigations include a serial session queue, late-frame dropping, a five-Hz segmentation throttle, weak preview/model links, a shared non-caching `CIContext`, 2000-pixel recognition input, and sequential multi-page processing.

## PERF-300: Canceled camera startup can restart the capture session after dismissal

Severity:
High

Confidence:
Strong Evidence

Category:
Other

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/ReceiptCameraView.swift`
- Lines: 68-69, 258-308, 431-469
- Symbol: `ReceiptCameraView.body`, `ReceiptCameraModel.start()`, `stop()`, `stopSession()`, `onSessionQueue(_:)`

Description:
The SwiftUI `.task` that starts the camera is canceled when the view disappears, but `start()` never observes cancellation. `stop()` enqueues fire-and-forget teardown. If dismissal occurs while authorization or initial configuration is suspended, teardown can run first and the canceled startup task can subsequently configure and start the session, then install a new notification task after the view is gone.

Root Cause:
Desired lifecycle state is not serialized with AVFoundation work. Queue ordering protects individual session calls, but there is no cancellation/generation guard between awaits and no awaited teardown that prevents a later `startRunning()` from a stale startup.

Trigger:
Open the receipt camera and dismiss it quickly during first configuration or another suspended startup step.

Impact:
The camera session and frame-segmentation pipeline may remain active without visible UI, consuming camera, CPU, and energy resources until the owning model is released or another stop happens. It can also recreate the subject-area notification consumer after `stop()` canceled the previous one.

Evidence:
`.task`/`.onDisappear` invoke independent start and stop paths at lines 68-69. `start()` awaits authorization, configuration, and `startRunning()` at lines 258-270 without a cancellation check, then creates `subjectAreaTask` at lines 282-289. `stopSession()` only enqueues `stopRunning()` at lines 431-434. A serial queue permits the sequence `configure -> stop -> start` when stop is queued while configure is in flight.

Recommended Optimization:
Track a main-actor desired-running generation. Check cancellation/generation after every suspension and immediately before and after queued `startRunning()`. Serialize start and stop as one lifecycle protocol on the session queue, and ensure a canceled startup finishes by stopping rather than installing observers/torch state.

Trade-offs:
Awaiting teardown can delay dismissal if exposed directly to the UI; teardown may remain asynchronous, but ordering and desired-state checks must guarantee that stale startup cannot win. Avoid blocking the main actor on AVFoundation calls.

Validation:
Add session lifecycle signposts and an injectable delayed session/authorization seam. Repeatedly present and immediately dismiss on device, then verify `session.isRunning == false`, the frame delegate stops receiving buffers, the subject-area task is absent, and Energy Log shows no camera activity after dismissal.

Estimated Effort:
Medium

## PERF-301: Full-resolution receipt cropping runs on the main actor

Severity:
High

Confidence:
Strong Evidence

Category:
CPU

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/ReceiptCameraView.swift`
- Lines: 315-340, 364-405, 662-674
- Symbol: `ReceiptCameraModel.capture()`, `cropped(_:to:)`, `UIImage.uprightPixels()`

Description:
After photo capture resumes, the `@MainActor` model synchronously uprights and/or redraws the camera image, creates a full-resolution masked crop with `UIGraphicsImageRenderer`, and only then returns to the view. The recognizer later downscales to 2000 pixels, so the UI actor pays for a potentially near-12MP render before the bounded OCR path begins.

Root Cause:
Image rasterization is implemented as actor-isolated static/helper work called directly from `capture()`. The session start/stop path was moved off-main, but the captured-photo transform was not.

Trigger:
Capture a receipt while a valid document quad is present, especially when orientation normalization is also required or the padded quad covers most of the sensor frame.

Impact:
Large bitmap allocation and drawing can stall shutter feedback/dismissal and spike peak memory on the UI actor. The source comments document that an incorrectly scaled full-frame redraw previously reached about 440 MB; scale 1 fixes that amplification but the remaining full-resolution draw is still material.

Evidence:
`ReceiptCameraModel` is `@MainActor`; `capture()` calls `Self.cropped` synchronously at line 338. `cropped` may call `uprightPixels()` and always performs another renderer draw for a valid quad at lines 364-405. No timing measurement was collected, so the user-visible stall remains unconfirmed.

Recommended Optimization:
Move orientation normalization and masking to a dedicated non-main image-processing executor, passing immutable/sendable pixel data across the boundary. Evaluate combining crop, orientation, and the eventual 2000-pixel downscale so a large intermediate is not rendered solely to be downscaled immediately afterward.

Trade-offs:
Cropping coordinates and image orientation must remain bit-for-bit correct, and UIKit image APIs have actor/Sendable constraints. A Core Image/Core Graphics implementation may be safer than marking `UIImage` unchecked-sendable. Preserve the visible-quad crop semantics and receipt accuracy fixtures.

Validation:
Add signposts around capture callback, upright conversion, crop render, and recognition preparation. Profile on representative supported devices with a full 12MP frame using Time Profiler, Core Animation hangs, and Allocations; compare shutter-to-cover-dismiss latency, main-thread time, and peak resident memory while verifying crop fixtures.

Estimated Effort:
Medium

## PERF-305: Every receipt unconditionally performs two Vision document-recognition passes

Severity:
Medium

Confidence:
Strong Evidence

Category:
CPU

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReceiptTextRecognizer.swift`
- Lines: 24-56, 59-83, 188-222
- Symbol: `ReceiptTextRecognizer.recognize(in:)`, `enhanced(_:)`, `UIImage.preparedForRecognition()`

Description:
Every receipt runs `RecognizeDocumentsRequest` once on the prepared image, creates a second contrast-enhanced `CGImage`, and runs the same request again. The second pass is paid even when the first pass is already high-confidence and parses correctly.

Root Cause:
An earlier line-count gate did not identify low-light misrecognition, so the implementation deliberately switched to unconditional dual-pass OCR and selects by mean confidence.

Trigger:
Every camera or photo-library receipt scan.

Impact:
Vision CPU/Neural Engine work and scan latency are approximately doubled at the dominant recognition stage, with an additional bounded image buffer. The source records an observed order-of-magnitude of roughly one extra second, but this audit did not reproduce or measure it.

Evidence:
The plain request is awaited at line 41; enhancement is created at line 54; the second request is awaited at line 55. Both operate on the same capped 2000-pixel source. This is a concrete repeated expensive pattern, while the actual latency/energy impact remains unmeasured.

Recommended Optimization:
First establish confidence and parse-quality distributions across real/fixture receipts. If a reliable gate exists, run the enhanced pass only for low-confidence or structurally incomplete first-pass results. Keep unconditional dual-pass behavior when a gate cannot preserve the documented low-light/date/merchant accuracy.

Trade-offs:
This is an intentional quality-for-latency trade. Mean confidence alone may miss confidently wrong OCR, so a naive threshold can silently regress totals or dates. Do not change it without the existing end-to-end fixtures plus representative low-light captures.

Validation:
Signpost preparation, plain Vision, enhancement, and enhanced Vision separately. Measure scan latency, energy, and parse accuracy across well-lit, rotated, and low-light fixtures; derive a gate on a training subset and validate blind on held-out receipts.

Estimated Effort:
Medium

## Evidence limitations

- No physical-device camera run, Instruments capture, Energy Log, or Vision signpost baseline was available.
- AVFoundation callback timing and Vision cancellation behavior are inferred from control flow, not mocked in tests.
- The full-resolution crop and dual-pass findings are expensive patterns with strong static evidence, not measured bottlenecks.
