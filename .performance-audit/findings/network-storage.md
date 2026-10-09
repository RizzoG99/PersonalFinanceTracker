# WS-DATA: Persistence, I/O, and Caching Screening

## Scope and method

Static screening of the original `b91ee33` snapshot covered `TransactionActor`, repository/snapshot contracts, CSV/XLSX import and export, encrypted backup/restore, recurrence persistence, Safe-to-Spend and habit widget snapshots, the then-present daily forecast cache, and `FeatureDiscoveryService`. Call sites were inspected only to establish reachability and frequency. No profiler, SwiftData query trace, file-activity trace, benchmark, or device measurement was run, so this report contains no `Confirmed` findings.

## Finding summary

| ID | Severity | Confidence | Proposed priority | Title |
|---|---|---|---|---|
| PERF-200 | High | Strong Evidence | P1 | One data revision fans out into up to six full-store fetch-and-sort operations |
| PERF-201 | High | Strong Evidence | P1 | Mutation loops repeatedly rebuild snapshots and reload WidgetKit timelines |
| PERF-203 | Low | Strong Evidence | Resolved by PR #217 | Insights rewrites an unchanged forecast cache |

Cross-workstream note: PERF-200 is the storage/query amplification beneath the UI workstream's PERF-110 global-invalidation finding. Consolidation should keep one root cause while preserving PERF-200's repository-call evidence and validation counters.

## PERF-200: One data revision fans out into up to six full-store fetch-and-sort operations

Severity:
High

Confidence:
Strong Evidence

Category:
Storage

Location:

- File: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`
- Lines: 12-16
- Symbol: `TransactionActor.fetchAll()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift`
- Lines: 274-300
- Symbol: `MainTabView.body` data-revision handlers
- File: `PersonalFinanceTraker/PersonalFinanceTraker/App/AddTransactionIntent.swift`
- Lines: 131-149
- Symbol: `HabitSnapshotUpdater.refresh(using:)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard/DashboardViewModel.swift`
- Lines: 67-79
- Symbol: `DashboardViewModel.fetchAndCompute()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 213-223
- Symbol: `TransactionListViewModel.reload()` / `fetchAndRefresh()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`
- Lines: 89-110
- Symbol: `CompassViewModel.reloadData()`

Description:
Each `DataChangedSignal` revision independently reloads Dashboard, Activity, Insights, the habit-widget snapshot, the Safe-to-Spend snapshot, and the committed-spending detector on iPhone. Each path calls the same `fetchAll()` repository method. The actor serializes these requests, and every request fetches every transaction, orders it newest-first, materializes SwiftData models, and maps them into snapshots. The iPhone revision path therefore reaches up to six full-store reads; the analogous iPad path reaches five.

Root Cause:
Cross-feature invalidation is broadcast as a signal, but the refreshed consumers do not share one fetched snapshot or request the narrower data each computation needs. The only transaction read API is the ordered full-store `fetchAll()` contract, so analytics and widget calculations pay for the Activity list's sort even when order is irrelevant.

Trigger:
Adding, editing, deleting, bulk-editing, or importing transactions; recurrence changes that bump the signal; foreground refresh; and initial shell setup after it bumps the signal.

Impact:
With a multi-year ledger, one user mutation can enqueue several ordered full-store reads and `O(T)` snapshot mappings on the single repository actor before downstream calculations begin. The sort cost depends on SwiftData's generated query plan and available indexes, which were not inspected at runtime. The repeated reads can extend save-to-refresh latency, increase allocation/I/O churn, and delay unrelated repository work. Runtime impact has not been measured.

Evidence:

- `fetchAll()` unconditionally applies a descending timestamp sort and maps the complete fetch result.
- The iPhone revision handler starts Dashboard, Activity, and Insights reloads and explicit habit/Safe-to-Spend refreshes; the revision-keyed committed-spending task independently fetches the history.
- Dashboard, Activity, Insights, both widget refreshers, and `CommittedSpendingModel.reload` each call `repo.fetchAll()` rather than sharing a revision snapshot.

Recommended Optimization:
Introduce a revision-scoped data snapshot/coordinator that performs one repository read and distributes the immutable transaction/category/rule snapshots to interested view models, or add focused repository queries/aggregates for consumers that need only a date window, count, or totals. Keep an ordered full-history query for Activity, but do not impose it on order-insensitive consumers. Coalesce in-flight reloads for the same revision.

Trade-offs:
A shared snapshot needs clear freshness and ownership rules, and focused queries increase repository surface area. Aggregates must preserve currency conversion, goal-transfer exclusions, recurrence semantics, and exact period boundaries. Coalescing must not swallow a later revision.

Validation:
Seed realistic 1k, 10k, and 50k transaction stores; add `os_signpost` intervals around `fetchAll()` and revision handling; use Instruments' SwiftData/Core Data and Time Profiler templates to count store reads and wall time for one add/edit/import. Verify one revision does not show stale data in any shell, widget, or fixed-expense card.

Estimated Effort:
Large

## PERF-201: Mutation loops repeatedly rebuild snapshots and reload WidgetKit timelines

Severity:
High

Confidence:
Strong Evidence

Category:
Storage

Location:

- File: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`
- Lines: 19-36, 62-75, 78-120, 126-133, 153-178, 185-235, 428-440
- Symbol: cash-flow mutation methods and `refreshSafeToSpendWidgetSnapshot()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SafeToSpendSnapshotUpdater.swift`
- Lines: 9-30
- Symbol: `SafeToSpendSnapshotUpdater.refresh(...)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 825-846
- Symbol: `TransactionListViewModel.applyBulkEdit(...)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RestoreService.swift`
- Lines: 8-31
- Symbol: `RestoreService.restoreLatest(...)`

Description:
Most transaction and recurrence mutations synchronously await a Safe-to-Spend refresh after saving. That refresh fetches and sorts the full transaction store, fetches all recurrence rules before filtering active ones, recomputes the snapshot, writes app-group storage, and requests a WidgetKit timeline reload. Bulk edit calls `update` once per selected row. Restore separately deletes all transactions, deletes all rules, adds every recurrence rule one at a time, then adds the transaction batch; each of those steps invokes the refresh path.

Root Cause:
Snapshot invalidation is embedded in single-entity repository methods, with no transaction/batch boundary or dirty/coalesced refresh mechanism. The snapshot builder receives a full history even though it only consumes the current pay cycle, and timeline reload is unconditional.

Trigger:
Bulk category/type/amount/note edits and their undo path; backup restore; recurrence materialization across multiple rules; and any sequence of recurrence cursor updates.

Impact:
Editing `M` selected rows performs `M` saves, `M` ordered full-store fetches, `M` app-group writes, and `M` WidgetKit reload requests before the final cross-feature revision adds more refreshes. Restoring `R` recurrence rules similarly causes at least `R + 3` Safe-to-Spend refreshes. The multiplicative work is structurally present; latency, energy, and WidgetKit throttling effects are unmeasured.

Evidence:

- `TransactionActor.update` and recurrence mutations call `refreshSafeToSpendWidgetSnapshot()` after every save.
- `applyBulkEdit` awaits `repo.update` inside a loop.
- Restore loops over `addRecurrenceRule`; the delete-all methods and final `addBatch` also refresh.
- `SafeToSpendSnapshotUpdater.refresh` always writes and calls `WidgetCenter.shared.reloadTimelines`.

Recommended Optimization:
Add repository-level batch update and restore operations that save once and emit one snapshot invalidation. Model the widget snapshot as dirty and coalesce refreshes per logical mutation/revision. Push the Safe-to-Spend transaction date window and active-rule predicate into SwiftData, omit the unnecessary ordering, and skip the app-group write/timeline reload when the material snapshot is unchanged.

Trade-offs:
Deferred refresh can briefly leave the widget stale or lose the refresh if the process exits; use an explicit batch boundary with a guaranteed final flush rather than an arbitrary delay for restore/import. Batch operations need all-or-nothing error semantics and undo behavior. Equality checks should ignore or handle `generatedAt` so it does not force every write.

Validation:
Instrument repository saves, full-store fetches, snapshot writes, and `reloadTimelines` calls. Measure 1/10/100-row edits, undo, restore with realistic rules and transactions, and foreground materialization. Verify exactly one final widget refresh and that restore failure behavior remains correct.

Estimated Effort:
Medium

## PERF-203: Insights rewrites an unchanged forecast cache

> **Delta disposition:** Resolved by PR #217 (`dcbb22d`). The forecast service, cache model, repository APIs, and caller were removed. The evidence below is retained for the audited `b91ee33` snapshot; PERF-203 is excluded from the active roadmap and current root count.

Severity:
Low

Confidence:
Strong Evidence

Category:
Storage

Location:

- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SpendingForecastService.swift`
- Lines: 23-41
- Symbol: `SpendingForecastService.compute(...)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`
- Lines: 228-249
- Symbol: `CompassViewModel.computeForecast()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`
- Lines: 387-401
- Symbol: `fetchForecastCache()` / `saveForecastCache(_:)`

Description:
The forecast service explicitly recognizes an up-to-date cache and reuses its arrays without adding work, but the caller always creates `DailyForecastCacheData` and saves it. Saving fetches every cache row, deletes them all, inserts a replacement, and commits even when the values are identical.

Root Cause:
The compute API always returns a cache value but does not communicate whether persistence changed, and the repository implements replacement rather than a conditional singleton upsert.

Trigger:
Every Insights reload on the same day, including data revisions and foreground refreshes.

Impact:
Causes avoidable SwiftData fetch/delete/insert/save churn. The cache row is tiny, so this is unlikely to be user-visible in isolation; it matters mainly when compounded with the broader revision fan-out.

Evidence:
`cacheIsUpToDate` selects the reuse branch, while `computeForecast()` still unconditionally calls `saveForecastCache`; the save method unconditionally replaces all rows.

Recommended Optimization:
Return a `cacheChanged` flag or optional updated cache and save only when changed. Enforce or maintain a singleton and update it in place. Invalidate/update it explicitly when transactions affecting its covered interval change.

Trade-offs:
The current cache semantics may already be correctness-sensitive to same-day edits; performance work should first define invalidation so skipping a write does not preserve stale daily totals.

Validation:
Count SwiftData saves across repeated same-day Insights reloads, then add/edit/delete a current-month transaction and verify the forecast and persisted cache update correctly.

Estimated Effort:
Small

## Screened paths without an accepted finding

- Feature discovery performs at most one load per launch (`AuthenticationWrapper` has a completion guard). The localized-manifest request and fallback request are sequential only when needed, and bypassing the URL cache is documented as an editorial-freshness choice. No runtime evidence justifies changing it.
- Scheduled backups are gated to 24 hours and retained backups default to three. Serialization/encryption are whole-payload operations but no evidence showed unintended repetition.
- CSV parsing is explicitly detached from the main actor and stores raw rows for lazy column parsing. It still reads/decodes the whole selected file, but supported import-size limits and peak-memory measurements are absent, so this remains a validation note rather than a finding.
- Export paths intentionally materialize a complete user-requested file. Their peak allocation should be measured with a large fixture before adopting streaming complexity.

## Evidence limitations

This is static evidence only. SwiftData may optimize some sorts/fetches internally, WidgetKit may coalesce reload requests, and real ledgers/rule counts may be small. There are no checked-in large-data performance tests or signposts for these paths. P1 candidates require independent profiling before implementation.
