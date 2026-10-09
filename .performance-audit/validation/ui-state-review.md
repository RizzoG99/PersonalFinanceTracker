# Independent Validation: UI and State Findings

## Scope and standard

This review challenged PERF-110, PERF-111, and PERF-112 against current call chains, trigger multiplicity, task guards, existing off-main/cache mitigations, and the repository's realistic multi-year-ledger scenario. It is static validation only: no signposts, device traces, large-store timings, or frame-hitch measurements exist. Accordingly, all retained findings remain `Strong Evidence`, not `Confirmed`.

> **Delta note:** This review records the original `b91ee33` snapshot. PR #217 removed the forecast cache and traversal implementation described under PERF-112/PERF-204. The current disposition through `dcbb22d` is documented in `pr217-delta-review.md`; PERF-112 remains active on independent Dashboard and Insights evidence, while PERF-204 is retired.

## Verdicts

| ID | Verdict | Severity | Confidence | Priority | Consolidation |
|---|---|---|---|---|---|
| PERF-110 | Keep | High | Strong Evidence | P1 | Merge PERF-200 into this root finding |
| PERF-111 | Keep | High | Strong Evidence | P1 | Distinct from PERF-110; cross-reference it |
| PERF-112 | Keep | High | Strong Evidence | P1 | Merge PERF-204 into this root finding |

## PERF-110 — Keep, P1

Reachability and multiplicity are verified. `DataChangedSignal.bump()` has no scope. On iPhone, one revision starts Dashboard, Activity, and Insights reloads plus habit and Safe-to-Spend snapshot refreshes; the revision-keyed committed-spending task separately fetches the transaction history. PERF-200 verifies that this reaches up to six full, timestamp-sorted store reads for one revision. iPad reaches five. Dashboard and Activity `isLoaded` guards do not help because the shell calls `reload()`, which clears the guard.

Foreground is worse than a single revision: `MainTabView` starts the three model reloads, performs materialization/widget work, and then bumps the signal, starting another fan-out even if materialization changed nothing. Initial setup has a similar unconditional bump. These are common, reachable paths, not hypothetical calls.

High/P1 is justified by multiplicative full-store I/O and downstream CPU across hidden features. Keep the recommendation for scoped/coalesced invalidation, but establish repository-call baselines before choosing typed scopes versus a shared revision snapshot.

Correction: the original trigger wording should not imply all goal CRUD emits the global signal. Goal funding and budget/category-related paths do; plain goal add/edit/delete currently refresh goals locally.

Deduplication: PERF-200 is not a separate root cause. Fold its precise repository count, ordered-fetch evidence, and SwiftData validation plan into PERF-110, then retire PERF-200 as a standalone roadmap item.

## PERF-111 — Keep, P1

The duplicate-load claim is directly verified. `CompassView` attaches both `.payCycleAware { viewModel.load() }` and `.onAppear { viewModel.load() }`; `PayCycleAware` itself invokes the closure on appearance. `CompassViewModel.load()` has no task or loaded-state guard, so every appearance launches two complete reload tasks. Dismissing Add Transaction can launch another, while mutation callbacks and the global revision path can also reload the same model.

Dashboard and Activity do store task handles and have `isLoaded`, but `reload()` sets `isLoaded = false` and starts a new task without cancelling, awaiting, coalescing, or generation-checking the prior task. Representative recurrence and bulk-edit paths call both `onDataChanged` and local `reload`, proving another duplicate trigger family.

High/P1 remains justified because exact duplicate full refreshes occur on a normal navigation event and can overlap with PERF-110/112. The stale-publication concern remains a risk, not a reproduced defect. The proposed dirty-while-loading or generation-token approach is preferable to a simple `task != nil` guard, which could miss a mutation arriving after a fetch captured its snapshot.

## PERF-112 — Keep, P1

Main-actor execution is verified. Both view models are `@MainActor`. Dashboard detaches only `computeMetrics`; after awaiting it, Safe-to-Spend, quick templates, daily status, anomaly charting, budgets, and reminder checks run synchronously on the main actor. Insights invokes hero, explorer, habits, averages, health, and forecast services from main-actor-isolated methods without an executor hop.

The repeated work is structurally significant: `ExplorerBreakdown` builds three pie datasets plus period items; `FinancialHealthService` scans six monthly windows and then scans current-month expenses per budgeted category. PERF-204 adds forecast-specific evidence: even a warm cache leaves four full-history passes, while a cold/month-boundary cache can add one pass per elapsed day.

High/P1 is justified as a credible UI-responsiveness risk at multi-year scale, amplified by PERF-110/111, but it is not a measured hitch. Existing mitigations—Dashboard's detached first pass, recurrence detection off-main, and the forecast cache—reduce only portions of the workload.

Recommendation correction: prefer a dedicated non-main computation task/actor or bounded repository aggregates. Moving all pure analytics onto `TransactionActor` could serialize CPU work with persistence reads and writes. Preserve cancellation/generation checks before publishing results.

Deduplication: merge PERF-204's complexity and validation cases into PERF-112; do not count it separately in severity totals or the roadmap.

## Validation limitations and required measurements

- No checked-in benchmark establishes realistic upper transaction/category/rule counts; comments assume a personal ledger of a few thousand rows.
- SwiftData query duration, snapshot faulting, and allocation behavior are unknown.
- Main-actor duration and frame impact are unknown; High severity is a static risk rating, not proof of visible jank.
- Validate with 1k/5k/20k stores, repository-call counters, points-of-interest signposts, Time Profiler, Allocations, and SwiftData/Core Data instruments across Insights appearance, add/edit, bulk edit, cold launch, and no-op foreground.
