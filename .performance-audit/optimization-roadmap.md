# Performance Optimization Roadmap

## Decision rule

This roadmap sequences validation and future implementation. It does not authorize production changes. A finding advances only when its proposed metric shows material cost in a realistic scenario; otherwise retain the simpler implementation.

## Current checkpoint — 2026-10-16

Use [summary.md](summary.md) and `manifest.json.currentDisposition` for current status. The original stage ordering below is retained with completion notes; it is not a fresh list of outstanding fixes.

- PERF-110 refresh/cache/lifecycle work is mitigated in scope; PERF-101's original twice-per-body Activity category derivation is replaced by a single page value. No additional structural work is scheduled for either.
- PERF-111/#235 is mitigated in the verified ViewModel scope at `3402878`: shared refresh ownership and generation-guarded publication preserve pending updates. [Current report](measurements/PERF-111-insights-overlap.md) supersedes the earlier baseline. Stop structural work; physical/UI latency and independent CRUD tasks remain outside verification.
- PERF-112 is partial with its [5k service baseline and bounded follow-up](measurements/PERF-112-analytics.md) completed: Home cycle-summary CPU 12.43 → 2.11 ms in Release-TEST Simulator, covered Home service CPU 41.41 → 30.11 ms, all 70 result/count pairs matching. Stop structural work here; physical-device/richer-ledger measurements remain gates.
- PERF-303 is partial and further performance work is deferred after the user's reported improvement. Sleep cancellation exits correctly; filter supersession and `clearSearch()`'s multiple derivations remain unclosed. The physical search run establishes off-main filter intervals and input/UI work, not exact per-key latency or stale-result correctness.
- **PERF-201 bulk edit/Undo mitigation implemented and validated.** The [baseline](measurements/PERF-201-baseline.md) and [comparable batch follow-up](measurements/PERF-201-batch-followup.md) show per-row amplification replaced by one save/materialization/widget request per phase. Final-source 100-row medians are 215 ms edit / 204 ms Undo in Debug Simulator. Stop further structural work in this scope; physical responsiveness and restore/recurrence remain separate gates. The bounded PERF-112 service experiment is also complete; PERF-301 now has a bounded synthetic/device baseline and a no-optimization stop; further analytics work remains measurement-gated. New measurements get per-scenario notes under `measurements/`; do not create another competing overall follow-up index.

### PERF-201 first experiment — completed for bulk edit/Undo

1. Use the isolated **PFT TEST** 5,000-transaction fixture; preserve the personal installation. Run/seed once, then disable seeding and use the same build/instrumentation for comparisons. See [TEST setup](../docs/development/test-app.md).
2. Independently edit **1, 10 and 100** selected transactions, then exercise undo. Reset the fixture/state between equivalent repetitions and record selection semantics, device/build, warm state and baseline variance.
3. Count repository updates/saves, `TransactionActor.store.fetch` / `snapshots.map`, `SafeToSpend.refresh`, snapshot writes and WidgetKit requests. Measure operation-to-settled-state duration and main-thread work separately. Existing markers may need narrowly scoped additional save/operation boundaries; the source pattern alone is not a timing result.
4. Baseline completed in [PERF-201-baseline.md](measurements/PERF-201-baseline.md): 18 validated samples, N saves/full materializations/widget requests for N selected rows. Debug Simulator local settled median is about 11.6 seconds at 100 rows for edit and Undo. Main-thread/frame work and physical latency are not measured. Restore/recurrence are later extensions.
5. Completed: one explicit bulk edit/Undo boundary, operation-owned context, one successful save/flush, row-by-row retry after rollback on failure. Final app/widget values, selection scope, Undo, metadata and injected partial failures pass; all 18 follow-up samples meet count budgets. Physical timing and broader failure conditions remain unmeasured; no further structural change is scheduled in this scope.

## Priority map

| Original priority | Root findings | Current interpretation |
| --- | --- | --- |
| P0 | None | No emergency optimization is justified |
| P1 | PERF-110, PERF-111, PERF-112, PERF-201, PERF-301, PERF-303 | Follow the checkpoint above: mitigation/partial status differs by ID; PERF-201 bulk edit/Undo and the bounded PERF-112 experiment are complete in scope; PERF-301 has a bounded measured stop; do not reopen accepted scopes |
| P2 | PERF-100, PERF-101, PERF-202, PERF-205, PERF-300, PERF-302, PERF-305 | PERF-101 mitigated in scope; other candidates need current reachability/scale validation |
| P3 | PERF-102, PERF-400 | Keep simple unless targeted measurement changes the ranking |
| Resolved | PERF-203 | Removed by PR #217; retain only as historical audit evidence |

## Stage 0 — Measurement foundation

Established: opt-in recorder, deterministic fixture, focused tests, isolated TEST scheme with optimized profiling configuration, simulator ViewModel baseline and a physical-device search run. This is not baseline coverage for every P1. Native Points of Interest tables must be inspected when `os-log` is empty; sample weights remain distinct from frame latency.

1. Add deterministic large-data fixtures without replacing functional tests.
2. Add debug/test-only counters and signposts for repository reads, revisions, loader generations, snapshot writes, widget reloads, and receipt/search stages.
3. Record baselines for cold launch, foreground, add/edit, bulk edit, Activity search, Dashboard/Insights navigation, and receipt capture.
4. Store device, OS, build configuration, dataset shape, and run protocol beside every result.

Exit criterion: each P1 has a reproducible scenario and a baseline that can falsify the proposed optimization.

## Stage 1 — Low-risk duplication and cancellation

### PERF-303: search scheduling

- Done: cancellation escapes the debounce sleep. Further search performance work is deferred for now.
- Unify text/filter scheduling while preserving immediate filter-chip behavior.
- Remove redundant `clearSearch()` work.
- Add a latest-generation commit check and structured worker cancellation.

### PERF-111: duplicate loader entry points

- Completed in the #235 ViewModel scope: shared ownership for `load()` and awaited `reloadData()`, staged results and latest-generation publication, with pending follow-ups and retry coverage.
- [The current report](measurements/PERF-111-insights-overlap.md) records the red reproduction, 41 tests/44 passing executions and financial validation. PERF-112 remains accepted.
- Stop structural work in this scope. An already-issued daily snapshot save retains the existing history policy; physical/UI latency and independent goal CRUD remain outside this verification. #235 remains open for review.

## Stage 2 — Refresh and persistence amplification

### PERF-110: revision-scoped refresh coordination

- Implemented scoped mitigation: shared revision-aware immutable snapshots, mutation/external-write invalidation, bootstrap/foreground gates and coalesced refresh handling. Original six-fetch iPhone/five-fetch iPad patterns are historical baselines, not presumed current counts.
- Further typed invalidation/focused-query architecture is measurement-gated and not scheduled. The component extraction showed no clear simulator first-switch improvement; user-reported daily use now improved.
- Fold cold-launch PERF-401 and foreground PERF-402 into the same coordinator acceptance matrix.
- Preserve App Intent/external-change detection rather than simply removing refreshes.

### PERF-201: batch mutation boundaries

- Done in scope: explicit bulk edit/Undo boundary, justified by the 5k baseline and validated by a comparable follow-up. Restore and recurrence remain later, separately measured extensions.
- Implemented: save once normally; on batch failure, rollback/retry individual rows, then attempt the final Safe-to-Spend/widget refresh once after successful writes.
- Further material-output equality skipping is not implemented or scheduled; the batch removes measured multiplicity without a second optimization.

Exit criterion: repository read/save/write/reload counts scale with logical operations rather than row/rule count, with no stale UI or widget state.

## Stage 3 — Main-thread and media hot paths

### PERF-112: analytics execution — bounded experiment completed

- DateFormatter date-key hot path corrected. The [service-level baseline](measurements/PERF-112-analytics.md) now separates navigation, period/pay-cycle changes and mutation reloads on 5,000 deterministic records.
- Completed one measured windowing change: keep first-recorded metadata history-wide, but convert amounts only inside Home's current/three comparison cycles. CPU and full financial outputs were checked before/after.
- No executor, broad cache or aggregate-publication redesign is justified by this local baseline. Insights reload services total about 11 ms of covered main CPU in the optimized baseline; yearly exploration is a separate roughly 13 ms scope.
- Require an optimized physical-device recording or representative recurrence/goal/currency scale before more structural work. Insights task ownership/stale publication is separately mitigated under PERF-111/#235 at `3402878`; it is not a result of windowing.

### PERF-301: capture processing

- **User-accepted stop, 2026-10-16:** retain the restored production pipeline in the verified scope; no further optimization scheduled. [Acceptance and conditions](measurements/PERF-301-single-pass-experiment.md#user-acceptance--2026-10-16). The single-pass candidate failed real crop/OCR-input and recognized-line preservation on 1/8 photos despite synthetic CPU savings. Final restored parity is 8/8, regression 122 functions/148 executions; existing strict OCR accuracy failures remain separate. Other/older iPhones, updated physical before/after, exact memory peak/footprint and frame latency remain unverified. Reopen for new stall/memory-pressure evidence or a separately authorized bounded experiment.
- **Single-pass attempt completed and reverted:** user-authorized preventive experiment reduces synthetic rotated valid-crop CPU by 22–48%, but changes real crop/OCR-input pixels on 1/8 images and a recognized line list. Key fields retain their existing failures. Exact pre-experiment camera source restored; final 122 functions/148 executions pass, including 8/8 restored pixel comparisons. [Experiment/stop decision](measurements/PERF-301-single-pass-experiment.md). Stop this rendering attempt; no new generic device capture. Further approaches need a separate bounded decision.
- Updated base: local merge `e8df73f` imports main `cc86f16`, including rotation fix #243/#242. Preserves baseline WIP and camera fallback; no rendering optimization. [Integration/validation](measurements/PERF-301-main-sync.json). Earlier physical timings below are historical; use a comparable measurement on this base before a new experiment.

- **Current stop after run 4:** no processing optimization for the accepted interaction. Three captures repeat 222–252 ms main crop; 17 native VM snapshots show max resident 776.59 MiB / dirty 352.56 MiB, final dirty declining but above the prior plateau. Export remained enabled; no physical-footprint, transient-peak or leak proof. [Run-4 evidence](measurements/PERF-301-device-r4.json). Eight exported photo/quad pairs now have a red Release-TEST Simulator correctness baseline, repeated unchanged: total 7/8, date 8/8, exact merchant 3/8. Six original-without-crop controls do not establish a safe bypass. [Fixture evidence](measurements/PERF-301-device-fixtures.json). OCR/parser correctness is separate work; reopen performance only for a new stall or demonstrated sustained growth/pressure.
- PERF-301 is audit ID; [#241](https://github.com/RizzoG99/PersonalFinanceTracker/issues/241) is the GitHub ticket. [Baseline/protocol](measurements/PERF-301-receipt-processing.md) separates camera wait, callback construction, main-thread transforms, dismissal requests and OCR stages.
- Synthetic Release-TEST geometry/baseline and [one physical run-3 capture](measurements/PERF-301-device-r3.json) are available: crop 228.87 ms wall / 206.98 ms main CPU, OCR prep off-main. The user observes no slowdown/OCR errors; no optimization under the agreed gate. Export was active; peak footprint and frame latency remain unverified. Subsequent local-photo correctness failures are recorded above; no passing private-corpus parity is claimed. Rotation fix #243/#242 is now integrated from main. Keep raw images/traces local and ignored.
- No optimization retained. The preventive trial above was measured, rejected and reverted. A future bounded change requires new evidence or separate authorization; assess actual memory pressure separately. Preserve geometry/content/2000px OCR input and avoid unsafe sendability shortcuts.

Exit criterion: if the device cost is immaterial and use is acceptable, document and stop. Otherwise one causal change and one comparable follow-up, preserving OCR expectations; no automatic lifecycle or dual-pass OCR work.

## Stage 4 — P2 investigations

- PERF-100: measure iPad sorting before moving/caching derived state. PERF-101's original duplicate per-body evaluation is mitigated; only add category-scoping caches if profiles justify invalidation complexity.
- PERF-202: index recurrence candidates only after benchmarks show rule/history scale is material.
- PERF-205: optimize import matching only with realistic generated-row counts and exact parity tests.
- PERF-300: reproduce the dismissal race with a delayed session seam before changing lifecycle architecture.
- PERF-302: add task ownership when memory/concurrency traces show abandonment or overlap, or as part of receipt-flow hardening.
- PERF-305: derive any second-pass OCR gate from blind held-out accuracy data, not mean confidence alone.

## Stage 5 — P3 disposition

- PERF-102: reject caching if accessor cost is immaterial.
- PERF-400: retain synchronous launch design if avoidable pre-scene work is under budget; never trade away category readiness or file protection for an unmeasured gain.

## Delivery constraints for a future implementation session

- One root finding per change set unless two IDs were explicitly consolidated above.
- Establish baseline and acceptance metric before editing.
- Preserve behavior, financial calculations, recurrence semantics, app-intent freshness, widget freshness, crop geometry, and OCR accuracy.
- Run focused functional/regression tests and repeat the same performance protocol after the change.
- Record negative results and revert complexity that does not produce material improvement.
