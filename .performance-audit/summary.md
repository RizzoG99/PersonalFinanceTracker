# Performance Audit Summary

## Executive summary

This static audit found no measured or reproduced performance bottleneck. It found 21 raw candidates; independent review downgraded two severities and consolidated five overlapping items, leaving 16 distinct root findings. Six are P1 measurement-and-optimization candidates, seven are P2, and three are P3. There are no P0 findings.

The dominant concern is refresh amplification: one logical data change, cold-launch bootstrap, or iPhone foreground transition can cause several full, sorted SwiftData fetches, repeated widget snapshot work, and repeated feature analytics. That systemic fan-out makes otherwise reasonable per-feature work more expensive. The next strongest concerns are duplicated/overlapping loaders, main-actor analytics, per-row snapshot rebuilding during bulk operations, ineffective search cancellation, and full-resolution receipt cropping on the main actor.

The audit intentionally does not claim speedups. Every retained finding is either `Strong Evidence` from static control/data-flow analysis or `Potential`; none is `Confirmed` because no physical-device trace, large-store benchmark, SwiftData query trace, or memory profile was collected.

A focused delta review covers PR #217 through `dcbb22d`. It resolves PERF-203 and retires PERF-204's supporting evidence, leaving 15 active root findings: six P1, seven P2, and two P3. See `validation/pr217-delta-review.md`.

## Counts

### Original `b91ee33` raw validated observations

| Dimension | Count |
| --- | ---: |
| Total | 21 |
| High | 9 |
| Medium | 9 |
| Low | 3 |
| Confirmed | 0 |
| Strong Evidence | 18 |
| Potential | 3 |

### Original `b91ee33` consolidated root findings

| Dimension | Count |
| --- | ---: |
| Total | 16 |
| High / P1 | 6 |
| Medium / P2 | 7 |
| Low / P3 | 3 |
| Confirmed | 0 |
| Strong Evidence | 13 |
| Potential | 3 |

Consolidation retires PERF-200 into PERF-110, PERF-204 into PERF-112, PERF-304 into PERF-303, and treats PERF-401/PERF-402 as cold-launch and foreground validation scenarios for PERF-110 rather than separate implementation items. PR #217 later removed PERF-203 and the old forecast implementation supporting PERF-204; the other roots remain active after the focused delta review.

### Current disposition through `dcbb22d`

| Dimension | Count |
| --- | ---: |
| Active roots | 15 |
| High / P1 | 6 |
| Medium / P2 | 7 |
| Low / P3 | 2 |
| Confirmed | 0 |
| Strong Evidence | 12 |
| Potential | 3 |

## Repository coverage

- Main app composition, authentication/lock lifecycle, iPhone and iPad shells, and first-load/foreground behavior.
- SwiftUI rendering and observation in Activity, Dashboard, Insights, iPad ledger, lists, tables, and Charts consumers.
- SwiftData repository access, snapshots, recurrence, forecasts, budgets, Safe-to-Spend, imports, exports, backup/restore, and widget refreshes.
- Receipt camera, AVFoundation session lifecycle, Vision/Core Image recognition, image memory, task cancellation, and concurrency boundaries.
- Widget and app-group snapshot call sites, Feature Discovery networking, relevant unit/UI coverage, and the existing coarse warm-launch test.

The audit covered app-owned source and call sites, not third-party package internals.

## Findings by priority

### P0 — immediate

None. No issue has measured impact sufficient to justify P0.

### P1 — high-impact candidates

| Root ID | Finding | Confidence | Consolidated evidence |
| --- | --- | --- | --- |
| PERF-110 | Global revisions and lifecycle bootstrap fan out into repeated full refreshes | Strong Evidence | Includes PERF-200 query counts and PERF-401/PERF-402 launch/foreground triggers |
| PERF-111 | Reload ownership permits duplicate and overlapping full refresh tasks | Strong Evidence | Normal Insights appearance launches two reloads; mutation/global paths can overlap |
| PERF-112 | Dashboard and Insights run multi-pass history analytics on `MainActor` | Strong Evidence | Remains independently supported; PR #217 retired the PERF-204 forecast evidence |
| PERF-201 | Per-row/per-rule mutations repeatedly save, rebuild snapshots, and reload WidgetKit | Strong Evidence | Bulk edit and restore multiply full-store work |
| PERF-301 | Full-resolution receipt crop/render runs synchronously on `MainActor` | Strong Evidence | Large raster work precedes the later 2000-pixel OCR bound |
| PERF-303 | Search debounce and detached workers do not honor supersession correctly | Strong Evidence | Includes PERF-304 structured-cancellation/generation evidence |

### P2 — meaningful candidates requiring focused validation

- PERF-100: iPad ledger sorts the full visible dataset during view evaluation.
- PERF-101: Activity category scoping filters/allocates grouped rows twice per render.
- PERF-202: recurrence matching rescans full history per rule and due occurrence.
- PERF-205: import matching can approach quadratic work; realistic generated-row counts are unknown.
- PERF-300: camera startup can win after dismissal; independently downgraded from High because sustained post-dismissal ownership is unproven.
- PERF-302: receipt OCR tasks are not owned or canceled by the presenting lifecycle.
- PERF-305: every receipt unconditionally pays for two Vision recognition passes; accuracy trade-offs are substantial.

### P3 — low-impact or speculative

- PERF-102: Insights repeatedly derives the earliest transaction timestamp during view evaluation.
- PERF-400: required pre-scene store opening is synchronous; avoidable populated-store work appears limited to a count query and file-attribute checks, so optimize only if measured.

Resolved after the original snapshot: PERF-203. PR #217 removed the forecast cache path.

## Top 10 recommended optimizations

These are roadmap recommendations, not authorization to modify production code.

1. Introduce a measured, coalescing refresh coordinator with typed/scoped invalidation or one revision-scoped immutable snapshot (PERF-110).
2. Establish one reload owner per event and add dirty-while-loading/generation semantics so equivalent refreshes do not overlap (PERF-111).
3. Add repository batch boundaries for bulk edit, restore, and recurrence cursor changes, with one guaranteed final Safe-to-Spend/widget refresh (PERF-201).
4. Move only measured pure analytics to a dedicated non-main computation context or bounded database aggregates; publish one generation-checked result (PERF-112).
5. Make search/filter derivation cancel-and-replace correctly, allow sleep cancellation to exit, and prevent detached stale workers from publishing (PERF-303).
6. Combine receipt orientation, crop, and bounded downscale off the main actor without creating a full-resolution intermediate solely for OCR (PERF-301).
7. Give receipt recognition a single owned task per flow, cancel abandoned work, and prevent overlapping/stale completions (PERF-302).
8. Build a revision-scoped recurrence-payment index and batch cursor persistence only after parity benchmarks prove it worthwhile (PERF-202).
9. Derive iPad sorting and Activity category grouping once per relevant input change, starting with one-value-per-body quick fixes (PERF-100/PERF-101).
10. Measure OCR accuracy and latency before introducing a gate for the enhanced second Vision pass (PERF-305).

## Architectural performance concerns

1. `DataChangedSignal` is global and untyped, so unrelated/hidden features refresh together.
2. `fetchAll()` is the common contract even for consumers needing a window, count, unordered input, or aggregate.
3. Refresh ownership is split across views, view models, mutations, lifecycle handlers, and widget updaters.
4. Several pure history-wide computations remain main-actor isolated.
5. Per-entity repository methods embed cross-cutting widget side effects, preventing efficient batch boundaries.
6. Some unstructured/detached tasks make the visible cancellation API ineffective.

## Quick wins to validate first

- Let canceled search debounce sleep exit and remove `clearSearch()`'s duplicate explicit derivation.
- Remove the duplicated Insights appearance load after confirming pay-cycle behavior.
- Compute Activity's category-scoped rows once per body evaluation.

These are small changes, but they should still be implemented only in the separate optimization workflow with counters/tests proving behavior.

## Profiling recommendations

- Seed deterministic 1k, 5k, and 20k multi-year ledgers; use a larger stress case only to expose scaling behavior.
- Add points-of-interest intervals and counters around revisions, repository full fetches, model reloads, snapshot writes, WidgetKit reload requests, aggregate computation, search workers, and receipt stages.
- Use Time Profiler, SwiftUI, Hangs/Core Animation, Allocations/VM Tracker, SwiftData/Core Data, File Activity, Energy Log, and Swift Concurrency instruments as applicable.
- Measure on representative physical supported devices. Use simulator runs for deterministic correctness and coarse regression only, not camera, energy, memory-pressure, or final latency claims.
- Separate fresh-store cold launch, populated cold launch, warm launch, first unlock, no-op foreground, changed foreground, and navigation-to-screen measurements.

## Unverified hypotheses

- PERF-102 may be too cheap to justify caching.
- PERF-205 depends on real import and auto-generated-row sizes.
- PERF-300 proves a stale-start ordering but not sustained post-dismissal camera activity.
- PERF-305 may be an intentional and necessary quality/latency trade with no safe gate.
- PERF-400 may be dominated by unavoidable store opening, leaving no worthwhile optimization.

## Areas not analyzed or not measured

- No physical-device profiling, frame-rate trace, memory graph, energy log, jetsam data, camera lifecycle run, or OCR timing/accuracy experiment.
- No current SwiftData query plan, migration benchmark, database-size distribution, or field telemetry.
- No build-time/compile-time audit, dependency-source audit, or third-party package internals.
- No production user dataset or import-size distribution.
- No implementation, behavior change, dependency installation, or production test mutation.
- The focused PR #217 review covered only intersecting findings; it did not repeat unaffected workstreams or measure the richer month-card UI.

## Reports

- `architecture.md` — repository and performance-sensitive flow map.
- `audit-plan.md` — workstreams, scenarios, and evidence rules.
- `findings/rendering.md`
- `findings/state-management.md`
- `findings/network-storage.md`
- `findings/algorithms.md`
- `findings/memory.md`
- `findings/concurrency.md`
- `findings/platform-specific.md`
- `findings/startup.md`
- `validation/data-runtime-review.md`
- `validation/ui-state-review.md`
- `validation/startup-review.md`
- `validation/pr217-delta-review.md`
- `optimization-roadmap.md`
- `validation-plan.md`
