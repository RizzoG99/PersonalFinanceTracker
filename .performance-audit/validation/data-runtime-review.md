# Independent Validation: Data and Runtime Findings

## Scope and verdict summary

This review challenged PERF-200, PERF-201, PERF-300, PERF-301, and PERF-303 against their source call chains, expected event frequency, realistic input scale, and existing safeguards. It did not run Instruments, a camera device, or large-store benchmarks. Verdicts therefore validate static confidence and prioritization, not measured impact.

| ID | Verdict | Validated severity | Confidence | Priority |
| --- | --- | --- | --- | --- |
| PERF-200 | Keep | High | Strong Evidence | P1 |
| PERF-201 | Keep | High | Strong Evidence | P1 |
| PERF-300 | Downgrade | Medium | Strong Evidence | P2 |
| PERF-301 | Keep | High | Strong Evidence | P1 |
| PERF-303 | Keep | High | Strong Evidence | P1 |

No finding is `Confirmed`; none has runtime measurements. No P0 issue is justified.

## PERF-200 — Keep, High, P1

The six-fetch iPhone path is reachable for one revision:

1. Dashboard reload calls `fetchAll()` (`MainTabView.swift:274-275`; `DashboardViewModel.swift:67-79`).
2. Activity reload calls `fetchAll()` (`MainTabView.swift:276`; `TransactionListViewModel.swift:213-223`).
3. Insights load calls `fetchAll()` (`MainTabView.swift:277`; `InsightsViewModel.swift:80-110`).
4. Habit snapshot refresh calls `fetchAll()` (`MainTabView.swift:278-280`; `AddTransactionIntent.swift:131-150`).
5. Safe-to-Spend refresh calls `fetchAll()` (`MainTabView.swift:278-280`; `TransactionActor.swift:428-440`).
6. The revision-keyed committed-spending task calls `fetchAll()` (`MainTabView.swift:292-299`; `FixedExpensesSection.swift:84-104`).

Every `TransactionActor.fetchAll()` uses a descending timestamp descriptor and maps the complete result (`TransactionActor.swift:12-16`). The actor serializes access, which prevents simultaneous model-context use but does not remove any read, sort, or snapshot mapping. The iPad path lacks committed-spending detection and reaches five baseline reads.

High/P1 is justified because this happens on ordinary mutations, launch revision, and foreground revision, and cost scales with the complete ledger. SwiftData may optimize the store sort, and typical ledgers may be smaller than the proposed 50k stress case, so profiling remains mandatory.

Consolidation: PERF-200 is the storage evidence for PERF-110's global refresh fan-out. Keep one roadmap root cause, retaining PERF-200's exact repository-call counters and PERF-110's UI invalidation semantics.

## PERF-201 — Keep, High, P1

The multiplicative mutation path is definite. `applyBulkEdit` updates every selected transaction sequentially (`TransactionListViewModel.swift:825-846`); each `TransactionActor.update` saves, awaits `refreshSafeToSpendWidgetSnapshot()`, fetches the full sorted ledger and all active rules, writes the app-group snapshot, and requests a WidgetKit timeline reload (`TransactionActor.swift:78-95, 428-440`; `SafeToSpendSnapshotUpdater.swift:9-30`). Both iPhone and iPad expose select-all plus bulk category/amount/note actions, so large `M` is reachable rather than theoretical.

Restore also produces the reported `R + 3` refreshes: delete transactions, delete rules, add each of `R` rules, then add the transaction batch (`RestoreService.swift:8-31`). WidgetKit may internally throttle/coalesce timeline work, but the app still pays every save, full fetch, snapshot build, and write.

High/P1 and the batch-boundary recommendation are justified. The first optimization should be an explicit repository batch/restore transaction with one guaranteed final snapshot flush; an arbitrary debounce risks process-exit staleness.

Consolidation: PERF-201 shares PERF-200's expensive snapshot refresh primitive, but its root cause is distinct: per-entity mutation boundaries rather than broadcast invalidation. Track both under one broader “refresh amplification” initiative with separate acceptance metrics.

## PERF-300 — Downgrade to Medium, P2

The stale-start ordering is valid. `ReceiptCameraView` starts in a cancellable SwiftUI task and stops on dismissal (`ReceiptCameraView.swift:68-69`). `start()` awaits configuration and queued `startRunning()` without checking cancellation (`ReceiptCameraView.swift:258-291`), while `stop()` only appends fire-and-forget `stopRunning()` to the same serial queue (`ReceiptCameraView.swift:294-307, 431-442`). Dismissal during configuration can therefore order work as `configure -> stop -> stale start`.

Two limitations weaken High severity:

- Both production call sites check/request permission before presenting the camera (`ReceiptScanShortcut.swift:115-133`; `EditAddTransactionView.swift:303-321`), so suspension on the permission prompt is not a normal trigger. The race window is session configuration/startup.
- No long-lived owner was found after dismissal. The frame callback and notification task capture the model weakly, so static evidence proves a post-dismissal restart but not that the session remains active indefinitely after the canceled start task releases the model.

Keep Strong Evidence for the lifecycle defect, but use Medium/P2 until a device test shows sustained camera/frame/energy activity. The desired-running generation and ordered teardown recommendation remains appropriate.

## PERF-301 — Keep, High, P1

The capture path is reachable whenever live segmentation has a valid quad. `ReceiptCameraModel` is `@MainActor`; after photo capture, it synchronously calls `cropped` (`ReceiptCameraView.swift:191-193, 315-340`). Cropping may first upright the full image and then always renders the quad's full-resolution bounding box (`ReceiptCameraView.swift:364-405, 662-674`). The result is subsequently reduced to a 2000-pixel longest side for OCR (`ReceiptTextRecognizer.swift:188-222`).

For a near-full-frame 12MP receipt, this forces large decode/draw allocations and UI-actor CPU before dismissal and OCR progress. High/P1 is justified as a concrete UI-thread hazard, although shutter latency and peak resident memory remain unmeasured. The historical 440MB comment describes the fixed device-scale amplification and must not be presented as the current allocation. Combining orientation, crop/mask, and bounded downscale off-main is the strongest recommendation, subject to crop-coordinate fixtures and Sendable-safe image handling.

## PERF-303 — Keep, High, P1

The debounce is functionally defeated. Every keystroke cancels the previous task, but `try? await Task.sleep` swallows `CancellationError` and immediately continues to `doFilterItemBySearchText()` (`TransactionListViewModel.swift:110-120`). Non-empty search scans the full ledger in a detached task and publishes derived state (`TransactionListViewModel.swift:240-264`). Thus rapid typing starts approximately one full filter pipeline per keystroke instead of only the final one.

`clearSearch()` also schedules three derivations: `searchText.didSet`, `filters.didSet`, and an explicit task (`TransactionListViewModel.swift:448-453`). Even the fast path assigns `filteredItems`, triggering category/totals recomputation and grouping.

High/P1 is justified because rapid search is ordinary usage, work scales with ledger size, and the bug multiplies downstream derivation. Fixing the swallowed cancellation is small but incomplete: PERF-304 correctly notes that already-started detached workers do not inherit outer cancellation. Consolidate PERF-303 and PERF-304 under one search-generation/cancellation change, while preserving immediate filter-chip updates and debounced text input.

## Validation order

1. Add counters/signposts for repository full fetches, snapshot writes, and widget reload requests; validate PERF-200/201 with 1k/10k/50k fixtures.
2. Count filter starts/commits for a deterministic rapid-typing sequence; validate PERF-303/304 with thousands of rows.
3. Profile full-resolution capture on representative devices for main-thread time and peak memory (PERF-301).
4. Use a delayed injectable camera session to reproduce dismissal during configuration and determine post-dismissal lifetime before restoring High severity to PERF-300.
