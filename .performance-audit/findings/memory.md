# WS-RUNTIME — Memory and Resource Lifecycle

## Scope and method

Static screening covered the receipt capture/photo-library handoff, Vision/Core Image recognition, view-owned tasks, camera delegates, notification iteration, and the task handles in `TransactionListViewModel`. This report contains one accepted memory-lifecycle finding. No allocation, leak, memory-graph, or device-pressure measurement was run, so no finding is `Confirmed`.

The camera frame path already has useful bounds: late frames are discarded, segmentation is throttled, the preview layer is weakly held, delegate callbacks capture the model weakly, recognition input is capped at 2000 pixels on its longest side, and multi-page recognition is sequential. No static retain cycle was found in those paths.

## PERF-302: Receipt recognition work is not owned by the presenting view lifecycle

Severity:
Medium

Confidence:
Strong Evidence

Category:
Memory

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`
- Lines: 249-260, 326-360
- Symbol: `EditAddTransactionView.processReceiptImages(_:)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReceiptScanShortcut.swift`
- Lines: 83-94, 136-177
- Symbol: `ReceiptScanShortcut.processReceiptImages(_:)`

Description:
Both receipt entry points create unstructured `Task` values without retaining a handle. The tasks capture the selected/captured `[UIImage]` and continue through image preparation, two Vision passes, parsing, and (for the form path) merchant lookup even if the originating view disappears. Neither entry point rejects a second scan while recognition is already active.

Root Cause:
`isProcessingReceiptScan` and `isProcessing` are presentation flags, not ownership or cancellation mechanisms. The task handles are discarded, there is no cancellation on disappearance, and there is no single-flight guard before starting another recognition task.

Trigger:
Dismiss the add/edit form or navigate away from the shell while OCR is running, or initiate another receipt scan before the first one finishes.

Impact:
The task retains the receipt image and Vision/Core Image working data until completion after its UI is no longer useful. Overlapping scans can multiply those bounded but non-trivial buffers and compete for CPU/Neural Engine resources; a late task can also apply stale scan state.

Evidence:
The two call sites wrap work in bare `Task { ... }`, never assign the returned handle, and contain no `Task.isCancelled`/`checkCancellation()` checkpoints. `ReceiptTextRecognizer` keeps recognition inputs alive across asynchronous Vision calls. This proves continued ownership structurally, but peak retained bytes and user-visible pressure were not measured.

Recommended Optimization:
Give each flow one stored recognition-task handle, cancel-and-replace or reject while one is active, cancel on view disappearance, and add cancellation checks before parsing and before applying results. Keep the current sequential page processing and 2000-pixel cap.

Trade-offs:
Cancellation semantics must be explicit: dismissing the camera should cancel only abandoned recognition, while transitioning from successful shortcut recognition into the form must preserve the completed result. Vision cancellation support should be verified; even if an in-flight request cannot stop immediately, late state application can still be prevented.

Validation:
Use Allocations/VM Tracker while repeatedly starting a scan and dismissing during OCR. Add signposts for task start/cancel/finish, assert only one active scan, and verify memory returns to a stable band. Exercise form dismissal, tab switching, and rapid repeat scans with different receipts to detect stale completion.

Estimated Effort:
Medium

## Evidence limitations

- Static inspection cannot prove that Vision promptly observes Swift task cancellation.
- No device memory graph, jetsam log, retained-size measurement, or repeated-navigation trace was collected.
- Debug-only pixel fingerprinting was inspected but is excluded from release-cost conclusions.
