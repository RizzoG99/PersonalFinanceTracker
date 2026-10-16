# Performance Validation Plan

## Evidence status

Reconciled 2026-10-16 through review corrections `8dbb9e4` and the TEST/publication checkpoint in [summary.md](summary.md). [summary.md](summary.md) and `manifest.json.currentDisposition` are the current status index. The scenarios below retain original baselines and acceptance gates; they are not all outstanding implementation tasks.

PERF-110's earlier multiplicity and PERF-111's duplicate Insights appearance ownership/overlap were confirmed in the original measurement campaign. Scoped cache, lifecycle and loader fixes are implemented. Insights overlap is mitigated at the shared ViewModel owner under PERF-111/#235; independent CRUD task ownership and physical frequency/latency remain outside that verification. PERF-112's DateFormatter hot path and a measured Home cycle-summary conversion window are corrected; its 5k service baseline is complete, with physical-device/richer-ledger gates retained. PERF-101's original double evaluation is replaced by a single Activity page value per body.

Search now has both a [ViewModel 5k baseline](measurements/Activity-search-5k-baseline.md) and a [saved physical iPhone 14 Pro Max run](measurements/Activity-search-5k-device-r1.md). The old missing-run-3 request is superseded by the separate physical trace, explicitly analyzed at run 1. Filters run off-main at 24–61 ms; group assignment is below 0.54 ms. User reports a substantial overall improvement with mild typing lag and no perceived freeze. Per-key/frame latency and stale-result suppression remain unverified. Further search/first-switch optimization is deferred for now; retain PERF-303's unclosed correctness scenarios, including `clearSearch()`'s multiple derivations.

**PERF-201 baseline completed:** [1/10/100-row bulk note edit and Undo](measurements/PERF-201-baseline.md) on an isolated disk-backed TEST 5k fixture. All 18 samples passed correctness checks and show per-row save/fetch/map/widget amplification. The [implemented batch follow-up](measurements/PERF-201-batch-followup.md) now passes one-save/materialization/widget budgets in all 18 samples, with 100-row medians of 215 ms edit / 204 ms Undo in Debug Simulator. Physical responsiveness remains unmeasured. Exact memory peaks, energy, iPad timing and broader repeated physical-device scenarios remain unmeasured. Later receipt stage/VM observations and the red OCR replay are documented under PERF-301; they do not establish passing accuracy or post-integration physical-camera validation. Earlier tests/profiles are not rerun by this checkpoint; the new PERF-201 test and its exact results are recorded separately.

## Common protocol

- Build a Release-like profiling configuration with diagnostics consistent across runs.
- Use deterministic stores at 1k, 5k, and 20k transactions with realistic dates, categories, goals, travels, recurrence rules, and currencies. Treat larger stores as stress tests, not representative claims.
- Run on a representative oldest supported physical device and a current physical device. Record device, OS, thermal state, build commit, dataset, and run count.
- Warm up where appropriate; separate cold, warm, unlock, foreground, navigation, and in-flow measurements.
- Collect points of interest, repository/task counters, Time Profiler, main-thread/hang data, Allocations, and SwiftData/Core Data activity. Add File Activity, Energy Log, Swift Concurrency, or camera-specific observation only where relevant.
- Compare medians and distributions, not a single run. Define numeric budgets only after baseline variance is known.

## PERF-110 — Global refresh fan-out

Scenario:
Cold launch with an existing PIN, no-op foreground, foreground after App Intent change, add/edit transaction, and goal funding. Include iPhone and iPad.

Baseline metrics:
Revision bumps; `fetchAll()` calls and duration; categories/goals/rules fetches; Dashboard/Activity/Insights loads; fixed-expense detection; snapshot writes; WidgetKit reload requests; foreground-to-interactive time.

Tools:
`OSSignposter`/points of interest, debug counters, SwiftData/Core Data Instruments, Time Profiler, and launch/foreground UI harnesses.

Optimization strategy:
Coalesce by logical revision, introduce scoped invalidation or a shared immutable snapshot, and emit lifecycle revisions only when needed while preserving external writes.

Validation:
Verify one settled refresh plan per logical event, current data in visible and subsequently opened screens, current widgets, correct recurrence materialization, and correct deep-link/App Intent behavior.

Expected qualitative outcome:
Repository and CPU work no longer repeats merely because multiple hidden consumers observe the same event.

Regression checks:
All transaction/goal/recurrence tests, widget snapshot tests, launch/unlock flows, foreground with/without external changes, iPhone/iPad shells.

## PERF-111 — Duplicate and overlapping loaders

Scenario:
Open Insights once; dismiss Add Transaction after save; fund a goal; run bulk edit; trigger a data revision during an in-flight load; rapidly background/foreground.

Baseline metrics:
Per-model load start/end/cancel/commit counts, concurrent loads, repository calls, generation published, and stale-result attempts.

Tools:
Task-generation counters, Swift Concurrency Instruments, points of interest, and deterministic delayed repository mocks.

Optimization strategy:
Remove duplicate appearance ownership and implement serialized/coalescing refresh with dirty-while-loading and latest-generation commit semantics.

Validation:
One effective refresh per logical event, no overlapping equivalent loads, no missed late mutation, and only the newest generation publishes.

Expected qualitative outcome:
Navigation and mutations stop launching redundant complete refreshes while freshness remains unchanged.

Regression checks:
Existing view-model tests plus new delayed-read sequences, repeated navigation, retry/error paths, and pay-cycle changes.

## PERF-112 — Main-actor history analytics

2026-10-16 scoped result: the [5k service baseline and bounded follow-up](measurements/PERF-112-analytics.md) measure synchronous wall/thread CPU separately from async load wall time. Release-TEST Simulator cycle-summary CPU is 12.43 → 2.11 ms after time-windowing conversion; covered Home service CPU is 41.41 → 30.11 ms. All 70 comparable records retain result/count/thread coverage parity. Fixed-date tests cover full summary/chart outputs, pay-cycle/DST boundaries, future spending and USD Decimal conversion. Sequential mutation freshness and selected-period retention are covered; overlapping Insights task supersession is separately mitigated under PERF-111/#235, with its own [reproduction and validation](measurements/PERF-111-insights-overlap.md). Device frame latency, allocations, energy, light/dark and compact/wide layouts, accessibility Dynamic Type and VoiceOver were not checked in this service-only experiment. Stop structural work pending a measurement that changes the decision.

Scenario:
Open Dashboard and Insights, switch periods/categories, add/edit a transaction, and foreground using each deterministic store size.

Baseline metrics:
Main-actor duration per service/aggregate, total reload duration, frame hitches, allocations, transaction passes, and cancellation/stale-commit counts.

Tools:
Time Profiler, SwiftUI/Hangs, Allocations, points of interest around every analytics service, and correctness snapshots.

Optimization strategy:
Bound data windows, reuse intermediate indexes, and move only measured pure work to a dedicated non-main computation context. Keep persistence actor availability and generation-checked publication.

Validation:
Compare every Decimal total, chart point, score, forecast, insight, and ordering against current outputs while measuring main-thread and end-to-end change.

Expected qualitative outcome:
Dashboard/Insights interactions remain responsive as history grows without increasing stale-state or concurrency risk.

Regression checks:
Dashboard, Insights, financial-health, forecast, chart, budget, currency, calendar-boundary, and mixed-goal tests.

## PERF-201 — Per-entity mutation amplification

Checkpoint: [baseline completed](measurements/PERF-201-baseline.md) for 1/10/100-row bulk note edit and Undo. For N selected rows, each phase performs N saves/full materializations/snapshot writes/widget requests. The 100-row Debug Simulator median is approximately 11.6 seconds; physical UI latency, broad real-store failure conditions, restore and recurrence remain unmeasured. Completed: one batch boundary and comparable follow-up; one save/materialization/widget request per phase, validated row-retry/rollback, monetary-widget freshness, metadata and Undo. Stop further structural work in this scope; broader failure conditions, restore/recurrence and physical timing remain separate gates. Use the isolated TEST app; [setup](../docs/development/test-app.md).

Scenario:
Bulk edit and undo for 1/10/100 rows; restore with 0/10/100 recurrence rules; recurrence materialization with multiple due rules; inject a mid-batch failure.

Baseline metrics:
SwiftData saves, full-store fetches, rule fetches, snapshot builds/writes, WidgetKit reload requests, elapsed time, and partial-failure state.

Tools:
Repository counters, SwiftData/File Activity instruments, points of interest, deterministic failure-injection repository/storage seams.

Optimization strategy:
Implemented for bulk edit/Undo: one batch save normally, rollback and independent row retries on failure, then one final snapshot refresh attempt after successful persistence. Material-output equality skipping is not implemented or scheduled; restore/recurrence remain later gates.

Validation:
Counts scale with a logical batch rather than selected rows/rules; final app/widget state is current; failure and undo semantics match the contract.

Expected qualitative outcome:
Large bulk/restore operations avoid multiplicative persistence and widget side effects.

Regression checks:
Bulk editing, undo, restore, recurrence, Safe-to-Spend snapshot, and WidgetKit routing tests.

## PERF-301 — Full-resolution main-actor crop

Scenario:
Capture full-frame and partial receipts at representative camera resolution, including rotated images and valid/invalid quads.

Baseline metrics:
Capture callback-to-UI transition, main-thread time, crop/downscale duration, peak resident/bitmap memory, allocations, and OCR input dimensions.

Tools:
Time Profiler, Hangs/Core Animation, Allocations/VM Tracker, points of interest, and image/crop fixture comparisons on device.

Optimization strategy:
Perform orientation, mask/crop, and bounded downscale on a safe non-main pixel-processing boundary, avoiding unnecessary full-resolution intermediates.

Validation:
Reduce main-actor/peak-memory cost while preserving pixel orientation, quad geometry, visible crop, OCR accuracy, cancellation, and camera dismissal.

Expected qualitative outcome:
Receipt capture transitions promptly to processing without a large UI-thread rasterization step.

Regression checks:
Crop/orientation fixtures, camera/photo-library flows, low-light receipts, cancellation/dismissal, and memory stability across repeated scans.

## PERF-303 — Search cancellation and generation

Checkpoint: partial, further performance work deferred. Canceled sleep exits; the filter worker still lacks a latest-generation publication check, detached work can outlive its owner, and `clearSearch()` schedules multiple derivations. The physical run does not exercise/prove all cancellation races. Reopen with a deterministic correctness loop or disruptive user observation, not solely because the original finding is listed below.

Scenario:
Type a deterministic rapid sequence, change filter chips during debounce, clear search, and trigger a repository refresh with thousands of transactions.

Baseline metrics:
Debounce tasks, filter workers started/canceled/finished, grouping workers, full-array scans, committed generations, main-thread assignment time, and result latency.

Tools:
Task counters, points of interest, Swift Concurrency Instruments, Time Profiler, and deterministic delayed worker seams.

Optimization strategy:
Propagate cancellation, use structured/cancelable workers, distinguish immediate filter changes from debounced text, and gate publication by latest generation.

Validation:
Only the final debounced text derivation commits, clear performs one derivation, immediate chip changes stay immediate, and results always match current inputs.

Expected qualitative outcome:
Rapid input cost approaches one useful derivation rather than one complete pipeline per keystroke.

Regression checks:
Search/filter semantics, localized matching, grouping/travel sections, category totals, empty states, rapid clear, and concurrent reloads.

## P2/P3 measurement gates

- Rendering (PERF-100/101/102): count sort/filter evaluations and allocations during selection, search, and period navigation; reject caching if inclusive body cost is immaterial.
- Recurrence/import (PERF-202/205): benchmark realistic and worst-case matrices with exact result parity before indexing.
- Camera/OCR lifecycle (PERF-300/302/305): use delayed startup, repeated dismissal, Allocations/Energy Log, and blind held-out receipt accuracy before changing lifecycle or dual-pass policy.
- Startup (PERF-400): signpost store open, count/seed, and protection separately on fresh, populated, and migration-sized stores; preserve required readiness/security.
