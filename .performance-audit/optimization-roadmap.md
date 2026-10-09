# Performance Optimization Roadmap

## Decision rule

This roadmap sequences validation and future implementation. It does not authorize production changes. A finding advances only when its proposed metric shows material cost in a realistic scenario; otherwise retain the simpler implementation.

## Priority map

| Priority | Root findings | Decision |
| --- | --- | --- |
| P0 | None | No emergency optimization is justified |
| P1 | PERF-110, PERF-111, PERF-112, PERF-201, PERF-301, PERF-303 | Instrument, reproduce, then implement one at a time |
| P2 | PERF-100, PERF-101, PERF-202, PERF-205, PERF-300, PERF-302, PERF-305 | Profile after P1 baselines or when the specific flow is user-reported |
| P3 | PERF-102, PERF-400 | Keep simple unless targeted measurement changes the ranking |
| Resolved | PERF-203 | Removed by PR #217; retain only as historical audit evidence |

## Stage 0 — Measurement foundation

1. Add deterministic large-data fixtures without replacing functional tests.
2. Add debug/test-only counters and signposts for repository reads, revisions, loader generations, snapshot writes, widget reloads, and receipt/search stages.
3. Record baselines for cold launch, foreground, add/edit, bulk edit, Activity search, Dashboard/Insights navigation, and receipt capture.
4. Store device, OS, build configuration, dataset shape, and run protocol beside every result.

Exit criterion: each P1 has a reproducible scenario and a baseline that can falsify the proposed optimization.

## Stage 1 — Low-risk duplication and cancellation

### PERF-303: search scheduling

- Allow cancellation to escape the debounce sleep.
- Unify text/filter scheduling while preserving immediate filter-chip behavior.
- Remove redundant `clearSearch()` work.
- Add a latest-generation commit check and structured worker cancellation.

### PERF-111: duplicate loader entry points

- Remove the duplicated Insights appearance trigger.
- Add coalescing plus dirty-while-loading/generation semantics.
- Choose local refresh or scoped invalidation at mutation boundaries, not both.

Exit criterion: one effective derivation/reload per logical event, correct latest state, and no lost mutation refresh.

## Stage 2 — Refresh and persistence amplification

### PERF-110: revision-scoped refresh coordination

- Start with instrumentation of the six-fetch iPhone path and five-fetch iPad path.
- Choose between typed invalidation, a shared immutable revision snapshot, and focused queries based on measured consumers.
- Fold cold-launch PERF-401 and foreground PERF-402 into the same coordinator acceptance matrix.
- Preserve App Intent/external-change detection rather than simply removing refreshes.

### PERF-201: batch mutation boundaries

- Add explicit bulk edit/restore/recurrence batch operations.
- Save once when transaction semantics allow and flush Safe-to-Spend/widget state exactly once at a guaranteed boundary.
- Skip snapshot/timeline work when material output is unchanged.

Exit criterion: repository read/save/write/reload counts scale with logical operations rather than row/rule count, with no stale UI or widget state.

## Stage 3 — Main-thread and media hot paths

### PERF-112: analytics execution

- Measure service-level main-actor time first.
- Reuse intermediate windows/indexes and bound queries before introducing broad caching.
- Move measured pure computations to a dedicated non-main task/actor; do not serialize them onto `TransactionActor` if that would block persistence.
- Publish one immutable aggregate guarded by request generation.

### PERF-301: capture processing

- Preserve quad/orientation correctness fixtures.
- Combine orientation, crop/mask, and OCR-size bounding outside the main actor.
- Avoid unsafe `UIImage` sendability shortcuts; prefer an explicitly safe pixel-processing boundary.

Exit criterion: lower measured main-thread duration/peak allocation with identical financial aggregates and receipt geometry.

## Stage 4 — P2 investigations

- PERF-100/PERF-101: begin with compute-once-per-body changes; only add cached state if profiles justify invalidation complexity.
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
