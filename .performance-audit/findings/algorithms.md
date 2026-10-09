# WS-DATA: Algorithm and Hot-Path Screening

## Scope and method

Static screening covered recurrence detection/materialization, forecast, budget and chart aggregation, import deduplication, Safe-to-Spend calculation, repository snapshot conversion, and their realistic foreground/data-change call sites. Findings below describe concrete complexity or repeated traversal patterns, not measured bottlenecks. `PERF-200` in `network-storage.md` covers the higher-level repeated-fetch fan-out.

## Finding summary

| ID | Severity | Confidence | Proposed priority | Title |
|---|---|---|---|---|
| PERF-202 | Medium | Strong Evidence | P2 | Forecast-only recurrence matching rescans history per rule and occurrence |
| PERF-204 | Medium | Strong Evidence | Retired by PR #217 | Forecast computation repeatedly traverses the full expense history |
| PERF-205 | Medium | Potential | P2 | Import matching can degrade toward quadratic work |

Cross-workstream note: In the original `b91ee33` snapshot, PERF-204 was a forecast-specific subpath of the UI workstream's broader PERF-112 main-actor analytics finding. PR #217 removed that implementation, so its cold-cache `O((D + 4) * T)` evidence and validation matrix are retained below only as historical audit evidence.

## PERF-202: Forecast-only recurrence matching rescans history per rule and occurrence

Severity:
Medium

Confidence:
Strong Evidence

Category:
Algorithm

Location:

- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RecurrenceDetector.swift`
- Lines: 185-216
- Symbol: `RecurrenceDetector.paidThrough(...)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RecurrenceMaterializationService.swift`
- Lines: 28-37
- Symbol: `runMaterialization(using:today:calendar:)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Plan/FixedExpensesSection.swift`
- Lines: 84-104
- Symbol: `CommittedSpendingModel.reload(repo:)`

Description:
For each forecast-only rule, `paidThrough` filters the entire transaction history to produce candidate payments. For each due occurrence it then filters that candidate array again, computes the minimum distance, and removes the matched item with another linear pass. The same matching is reached from launch/foreground materialization and again from the revision-keyed committed-spending reload.

Root Cause:
Rules are matched independently against an unindexed full-history array. Candidate normalization/keying, amount comparison, date-window search, and removal are repeated rather than sharing an index across rules and invocations.

Trigger:
Launch/foreground, then every data revision on iPhone; cost grows with ledger size, number of forecast-only rules, and overdue occurrences.

Impact:
The initial candidate stage is `O(R * T)`. Occurrence matching adds up to `O(O * P)` per rule because each occurrence filters/minimizes and removes from the candidate list. Each successful cursor advance also triggers the snapshot amplification in PERF-201. Personal ledgers are expected to reach thousands of rows, but rule/occurrence counts and runtime cost are unmeasured.

Evidence:
Both callers iterate every forecast-only rule and pass the same complete transaction array. `paidThrough` performs a full `transactions.filter` for each call, then repeated `payments.filter(...).min(...)` and `removeAll` passes.

Recommended Optimization:
Build one revision-scoped index of unmatched expenses keyed by the same normalized commitment key plus a rounded/tolerance-friendly amount bucket, with entries ordered by timestamp. Search only the rule's relevant date range, consume matches by index, and batch all cursor advances into one repository save/snapshot refresh. Also avoid running the identical payment-matching pass twice during one foreground/revision cycle.

Trade-offs:
Amount tolerance does not map perfectly to a single bucket; adjacent buckets or a sorted range query may be required. Match consumption, closest-date tie-breaking, goal-vs-note identity, and ordering must stay identical. Shared caches need revision-based invalidation.

Validation:
Create deterministic matrices for 1/10/100 rules across 1k/10k/50k transactions, including many same-key candidates and overdue occurrences. Compare exact matched cursors/amounts with the current implementation and profile both materialization and committed-spending reload.

Estimated Effort:
Medium

## PERF-204: Forecast computation repeatedly traverses the full expense history

> **Delta disposition:** Retired as supporting evidence by PR #217 (`dcbb22d`). The implementation below was deleted; the replacement cycle summary uses one transaction loop. PERF-204 was already consolidated beneath PERF-112, whose remaining Dashboard and Insights evidence is still active.

Severity:
Medium

Confidence:
Strong Evidence

Category:
Algorithm

Location:

- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SpendingForecastService.swift`
- Lines: 55-84
- Symbol: `SpendingForecastService.compute(...)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`
- Lines: 89-110, 228-249
- Symbol: `CompassViewModel.reloadData()` / `computeForecast()`

Description:
Forecast computation filters the complete expense array once per uncached day in the current month, again for current-month spending, and once for each of the prior three months. Even with an up-to-date daily cache, aggregate metrics still make four full-history filtering passes. On a cold or month-boundary recompute, the daily loop can add up to 31 more passes. The computation is invoked from the `@MainActor` Insights model after each reload.

Root Cause:
Calendar buckets are calculated by repeatedly filtering the source array rather than assigning transactions to relevant daily/monthly buckets in one pass. The daily cache covers cumulative chart points but not the aggregate queries.

Trigger:
Opening/reloading Insights, every data revision, foreground refresh, and a new month or missing/stale cache.

Impact:
Steady-state complexity is at least `O(4T)` and a full daily recompute is `O((D + 4) * T)`, with repeated intermediate-array allocations and currency conversion. For a multi-year history, old transactions are reconsidered even though only four months affect the forecast. Main-thread responsiveness risk is credible but unmeasured.

Evidence:
The daily loop calls `expenseTransactions.filter` for each day; current month and each of three historical months filter the same input again. `CompassViewModel` is `@MainActor` and directly calls the pure service.

Recommended Optimization:
Compute the earliest relevant date, then make one pass over transactions to accumulate current-month daily totals, current-month total, and three prior monthly totals. Alternatively push the four-month date bound into a repository query and aggregate off-main. Preserve cache invalidation for same-day edits rather than relying only on `computedUpToDay`.

Trade-offs:
Single-pass bucket logic is more complex around calendars, time zones, month boundaries, and future-dated materialized transactions. Repository aggregation must preserve Decimal/currency conversion semantics.

Validation:
Benchmark cold-cache and warm-cache computation with realistic multi-year stores on supported devices; use Time Profiler and Allocations. Assert bit-for-bit `Decimal` results and daily point parity across leap years, month boundaries, mixed currencies, and future-dated rows.

Estimated Effort:
Medium

## PERF-205: Import matching can degrade toward quadratic work

Severity:
Medium

Confidence:
Potential

Category:
Algorithm

Location:

- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 1010-1043
- Symbol: `TransactionListViewModel.confirmImport(...)`

Description:
Exact duplicate detection is already indexed with a `Set`, but matching imported rows against previously auto-generated recurrence transactions scans `generated` with `firstIndex(where:)` for every input and shifts the array when removing a match.

Root Cause:
Generated rows are kept as a flat array despite matching on rounded amount and a three-day date window.

Trigger:
Confirming a large import when the store contains many auto-record-generated recurrence rows not eliminated by the exact duplicate key.

Impact:
Worst-case comparison work approaches `O(I * G)`, and repeated middle removals can add `O(G)` shifting per match. Typical `G` may be small, so user-visible impact remains a hypothesis until realistic generated-row counts are established.

Evidence:
The import loop calls `generated.firstIndex(where:)` once for each non-exact input, then `generated.remove(at:)`. No amount/date index bounds the search.

Recommended Optimization:
Index generated rows by rounded amount and a calendar-day bucket, checking only the target day and adjacent three-day buckets; store candidates in deques/sets or mark consumed IDs instead of shifting the array. Preserve one-to-one consumption.

Trade-offs:
Time zones, the inclusive three-day interval, cent rounding, sign, and one-match-per-generated-row semantics make the index easy to get subtly wrong. Do not add it unless a large-import benchmark shows material cost.

Validation:
Benchmark imports spanning 100/1k/10k rows against 10/100/1k generated rows, including worst-case same-amount nonmatches. Assert identical inserted/skipped counts and exact consumed-row behavior.

Estimated Effort:
Medium

## Screened paths without an accepted finding

- `BudgetProgressService` performs a single transaction pass plus small category mapping; no structurally significant issue was found.
- Chart services perform fixed 7/approximately 5/12 bucket scans. A single-pass bucketing implementation may be cleaner, but the bucket count is bounded and no evidence establishes it as a meaningful bottleneck.
- `RecurrenceDetector.detect` groups candidates before sorting/clustering and already runs detached in the frequent committed-spending path. Its whole-history recomputation should be profiled with PERF-202, but it was not separately labeled a bottleneck.
- Safe-to-Spend calculation itself is linear; the material issue is how often full histories are fetched and the calculation is invoked (PERF-200/PERF-201).

## Evidence limitations

No runtime sizes, execution counts, wall times, allocation traces, or query plans were collected. Calendar/currency work can have a higher constant factor than Big-O notation shows, while typical personal-finance datasets may keep all listed costs imperceptible. PERF-205 is deliberately `Potential`; PERF-202 remains a concrete but unconfirmed repeated-work pattern. PERF-204 was concrete in the original snapshot and was retired after PR #217 removed the implementation.
