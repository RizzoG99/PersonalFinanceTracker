# Rendering Static Screening

## Scope and method

Static screening covered the SwiftUI rendering paths in `Features/TransactionListView`, `Features/Insights`, and `Features/iPad`, with emphasis on realistic multi-year stores containing thousands of transactions. The review traced computed collections through their call sites, checked how often observation can invalidate each view, and accounted for existing background grouping, cancellation, and data-size bounds. No profiler or benchmark was run, so this report contains no `Confirmed` findings.

## Findings summary

| ID | Severity | Confidence | Area |
| --- | --- | --- | --- |
| PERF-100 | Medium | Strong Evidence | iPad ledger sorting |
| PERF-101 | Medium | Strong Evidence | Activity category grouping |
| PERF-102 | Low | Potential | Insights history-bound lookup |

## PERF-100: iPad ledger re-sorts the full visible dataset during view evaluation

Severity:
Medium

Confidence:
Strong Evidence

Category:
Rendering | CPU

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/iPad/IPadLedgerTable.swift`
- Lines: 28-30, 50-86, 153-179
- Symbol: `IPadLedgerTable.rows`, `IPadLedgerTable.body`, `IPadLedgerTable.table`

Description:
`rows` constructs a newly sorted array from every filtered transaction whenever the computed property is read. The render path reads it for the `Table` and again for the empty-state overlay; action closures and menus read it again when invoked.

Root Cause:
Sorting is expressed as an uncached view-computed property rather than derived state updated only when `filteredItems` or `sortOrder` changes. `IPadLedgerTable` also observes selection and filter state, so selection, sheet, search, and sort changes can re-evaluate the view even when the sort inputs did not materially change.

Trigger:
Opening the iPad Activity destination and any subsequent body invalidation, especially selecting rows, editing search/filter state, or changing the table sort order.

Impact:
For a realistic ledger with thousands of transactions, each evaluation performs an `O(n log n)` sort and allocates another array on the main actor before SwiftUI can update the table. This can increase input latency during selection and search and add allocation churn.

Evidence:
- Lines 28-30 call `viewModel.filteredItems.sorted(using: sortOrder)` with no cache or guard.
- Lines 82-85 read `rows.isEmpty` in the render chain.
- Lines 153-179 pass `rows` to `Table`, creating another read in the same logical render.
- `sortOrder` is state, but there is no stored derived collection or invalidation boundary tied specifically to `sortOrder` and `filteredItems`.

Recommended Optimization:
Maintain a derived sorted array that is recomputed only when the filtered source or sort order changes. A minimal first step is to compute the array once per body evaluation and pass it to table/overlay helpers; the stronger option is view-model or view-owned cached derived state with explicit invalidation.

Trade-offs:
Caching creates correctness risk if invalidation misses a transaction or comparator change. Moving sort work off-main requires immutable `Sendable` snapshots, cancellation, and a generation check so an older sort cannot replace a newer search result.

Validation:
Seed 1k, 5k, and 20k transactions; record Time Profiler and Allocations while opening Activity, selecting 20 rows, changing sort columns, and typing a search. Count sort invocations with a signpost. Compare main-thread time and allocation count before and after while verifying stable order and selection identity.

Estimated Effort:
Medium

## PERF-101: Activity's category lens filters and allocates grouped rows twice per render

Severity:
Medium

Confidence:
Strong Evidence

Category:
Rendering | CPU

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/ActivityView.swift`
- Lines: 74-89, 192-195, 267-272
- Symbol: `ActivityView.groupedFiltered`, `ActivityView.body`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 266-285
- Symbol: `TransactionListViewModel.updateGroupedItems()`

Description:
When a category chip is active, `groupedFiltered` walks every grouped row, filters each day's array, removes empty days, and creates new arrays. The same computed property is read once to build the list and again to decide whether to show the empty-search overlay.

Root Cause:
Category scoping is a view-time lens layered after the view model's already-derived `groupedItems`. The view model carefully moves grouping off the main actor and cancels stale grouping tasks, but the category-specific pass remains uncached on the main actor and is duplicated within the same body.

Trigger:
Any Activity body invalidation while a category is selected: selection changes, filter/search completion, local sheet presentation state, or refreshed grouped data.

Impact:
With thousands of visible transactions, the category-selected path performs two `O(n)` scans plus per-day array allocations before row diffing. It can erode scrolling or interaction responsiveness exactly when users are narrowing a large ledger.

Evidence:
- Lines 267-272 perform `compactMap` plus a nested `filter` across all grouped rows.
- Lines 74 and 193 read `groupedFiltered` independently in the same body.
- The existing optimization at `TransactionListViewModel.swift:266-285` only covers the upstream grouping and explicitly uses cancellation/background work; it does not mitigate this category pass.

Recommended Optimization:
At minimum, bind a single local category-scoped result per body so the list and overlay share it. Prefer deriving category-scoped grouped rows when `groupedItems` or `effectiveCategory` changes, with cancellation/generation protection similar to `updateGroupedItems()`.

Trade-offs:
Persisting another derived collection increases state and invalidation complexity. A single local value removes duplicate work but still leaves one main-thread full scan, which may already be sufficient if profiling shows the dataset is small.

Validation:
Profile Activity with 1k, 5k, and 20k transactions distributed across many days. Select a common and a rare category, then scroll, select rows, and edit search text. Signpost category-lens evaluations and compare invocation count, main-thread duration, and allocations. Verify totals, empty state, travel expansion, and row identity.

Estimated Effort:
Small | Medium

## PERF-102: Insights re-scans all transactions for the earliest date during body evaluation

Severity:
Low

Confidence:
Potential

Category:
Rendering | CPU

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`
- Lines: 55-63
- Symbol: `CompassViewModel.firstTransactionDate`, `CompassViewModel.canGoToPreviousPeriod`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/BreakdownExplorerSection.swift`
- Lines: 71-72, 78-87
- Symbol: `BreakdownExplorerSection.body`, `BreakdownExplorerSection.navigator`

Description:
`canGoToPreviousPeriod` calls `firstTransactionDate`, which finds the minimum by traversing the entire transaction array. The navigator reads this derived property while building the Insights body, and the custom-range sheet asks for the same minimum again when presented.

Root Cause:
An invariant that changes only when the loaded transaction snapshot changes is calculated lazily at view-read frequency rather than once during `reloadData()`.

Trigger:
Insights body invalidations such as changing periods or data type, presenting the custom-range sheet, toggling health-score options, or receiving refreshed model state.

Impact:
This adds an `O(n)` main-actor traversal to otherwise lightweight navigator updates. The absolute cost may be negligible for current stores, so it remains a hypothesis until measured.

Evidence:
- `transactions.lazy.map(\.timestamp).min()` at line 57 necessarily visits the complete collection.
- `canGoToPreviousPeriod` calls it at line 62, and the previous-period button reads that property at line 86.
- No cached earliest timestamp is stored during the full reload that already owns the source array.

Recommended Optimization:
Only if profiling shows material cost, compute and store the earliest timestamp when `transactions` is replaced, or return it as part of the off-main Insights aggregate proposed in the state-management report.

Trade-offs:
The current implementation is simple and always correct. A cache adds invalidation responsibility for a likely small cost, so no change is justified without a realistic-data measurement.

Validation:
Measure the accessor with 1k, 5k, and 20k snapshots and count calls while navigating periods and opening the custom range. Reject the optimization if the inclusive body-update cost remains immaterial.

Estimated Effort:
Small

## Screened but not accepted as findings

- `HealthScoreDetailView.sortedSnapshots` is bounded to six fetched snapshots, so its view-time sort is not material.
- `ForecastCard` and chart point mapping are bounded to roughly one financial month.
- Goal transfer totals are `O(goals * transactions)`, but realistic goal counts are small and no evidence yet shows user-visible cost; measure before considering an index.
- The primary Activity grouping already runs in a detached task and cancels stale results before publishing, so the grouping algorithm itself was not reported here.
