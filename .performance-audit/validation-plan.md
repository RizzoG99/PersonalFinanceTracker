# Performance Validation Plan

## Evidence status

No finding is currently `Confirmed`. This plan defines how to measure the six consolidated P1 findings and how to reject optimizations that do not produce a material benefit without compromising correctness.

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

Scenario:
Bulk edit and undo for 1/10/100 rows; restore with 0/10/100 recurrence rules; recurrence materialization with multiple due rules; inject a mid-batch failure.

Baseline metrics:
SwiftData saves, full-store fetches, rule fetches, snapshot builds/writes, WidgetKit reload requests, elapsed time, and partial-failure state.

Tools:
Repository counters, SwiftData/File Activity instruments, points of interest, deterministic failure-injection repository/storage seams.

Optimization strategy:
Explicit batch transactions with one final guaranteed snapshot flush and material-output equality checks.

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
