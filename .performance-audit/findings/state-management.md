# State Management Static Screening

## Scope and method

Static screening covered observation, refresh fan-out, task lifecycle, and main-actor analytical work across `MainTabView`, the iPad shell, `DataChangedSignal`, `TransactionListViewModel`, `DashboardViewModel`, and `CompassViewModel`. Reachability was traced from concrete appearance, foreground, and mutation hooks. Existing load guards, cancellation, detached work, and cache behavior were considered. No runtime instrumentation was available, so all accepted findings are `Strong Evidence`, not `Confirmed`.

## Findings summary

| ID | Severity | Confidence | Area |
| --- | --- | --- | --- |
| PERF-110 | High | Strong Evidence | Global refresh fan-out |
| PERF-111 | High | Strong Evidence | Duplicate/overlapping reload tasks |
| PERF-112 | High | Strong Evidence | Main-actor analytics |

## PERF-110: Every global data signal eagerly refreshes all feature models and hidden tabs

Severity:
High

Confidence:
Strong Evidence

Category:
State Management | Storage | CPU

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Models/DataChangedSignal.swift`
- Lines: 8-15
- Symbol: `DataChangedSignal.bump()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift`
- Lines: 274-281, 304-318, 335-342
- Symbol: `MainTabView.body`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/iPad/IPadRootView.swift`
- Lines: 87-115
- Symbol: `IPadRootView.body`

Description:
A single revision counter represents every persisted-data change. Both shells respond by reloading Dashboard, Activity, and Insights, plus refreshing habit and Safe-to-Spend widget snapshots, regardless of the affected entity or visible destination.

Root Cause:
The signal carries no change scope, dirty-feature information, or coalescing semantics. Feature models independently fetch overlapping full datasets, so one small mutation becomes multiple repository reads and complete analytical refreshes. Foreground handling first starts the three reloads and later bumps the signal, causing the same fan-out again even when materialization made no change.

Trigger:
Any `dataChanged.bump()` from transaction/goal flows, the initial shell task, and every transition to `.active`. The pattern is present in both the iPhone and iPad shells.

Impact:
Adding or editing one transaction can refresh three feature models and two widget pipelines, including models for off-screen tabs. A foreground event can schedule two rounds. With multi-year history this amplifies storage reads, CPU, allocation pressure, and battery use and increases the probability of main-thread work described in PERF-112.

Evidence:
- `DataChangedSignal` exposes only an incrementing integer (`DataChangedSignal.swift:11-15`).
- `MainTabView.swift:274-281` unconditionally reloads all three models and two snapshots.
- `MainTabView.swift:308-318` reloads all three on active, then bumps the signal after background work; the bump re-enters lines 274-281.
- `MainTabView.swift:335-342` preloads Activity, performs snapshot work, and bumps again during initial task execution.
- `IPadRootView.swift:98-105` contains the same all-feature fan-out and snapshot refreshes.
- Dashboard and Transaction list guards do not mitigate this path because the shell calls `reload()`, which clears `isLoaded`.

Recommended Optimization:
Introduce a refresh coordinator or typed change scope that coalesces revisions and invalidates only affected aggregates. Keep one authoritative post-mutation refresh, avoid a second foreground bump when nothing changed, and defer off-screen feature recomputation until selection/appearance unless a background consumer genuinely requires it. Instrument repository calls before choosing between fine-grained scopes and shared snapshot fan-out.

Trade-offs:
Selective/lazy refresh can expose stale cards or widgets if dependency mapping is incomplete. A coordinator adds state-machine and cancellation complexity. Correctness requires documenting which mutations affect Dashboard, Activity, Insights, recurrence detection, and each widget snapshot.

Validation:
Add repository-call counters/signposts and run cold launch, no-op foreground, add transaction, edit transaction, goal funding, and bulk edit with a 5k+ store. Record calls to full transaction/category/goal fetches and widget snapshot builders. Verify all visible and subsequently opened tabs remain current. A successful change should reduce duplicate work without weakening freshness.

Estimated Effort:
Large

## PERF-111: Reload entry points permit duplicate and overlapping full refresh tasks

Severity:
High

Confidence:
Strong Evidence

Category:
State Management | Concurrency

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsView.swift`
- Lines: 52-56
- Symbol: `CompassView.body`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/PayCycleAwareModifier.swift`
- Lines: 3-11
- Symbol: `PayCycleAware.body`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`
- Lines: 80-110, 154-168
- Symbol: `CompassViewModel.load()`, `reloadData()`, `addFunds(amount:to:)`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Lines: 202-224, 315-327, 825-847
- Symbol: `TransactionListViewModel.load()`, `reload()`, mutation tasks
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard/DashboardViewModel.swift`
- Lines: 45-65
- Symbol: `DashboardViewModel.load()`, `reload()`

Description:
Insights attaches both `payCycleAware` and a separate `onAppear`, and both immediately call an unguarded `CompassViewModel.load()`. Mutation methods also frequently reload locally and invoke `onDataChanged`, whose shell subscriber reloads the same model again. Dashboard and Transaction list retain task handles but `reload()` neither cancels nor awaits the in-flight task.

Root Cause:
Refresh ownership is split between views, view models, and the global signal. The loaders do not coalesce equivalent requests, cancel superseded work, or reject stale completions. `CompassViewModel` has no `isLoaded`/task guard at all.

Trigger:
- Every appearance of Insights: `PayCycleAware.onAppear` and `CompassView.onAppear` both call `load()`.
- Dismissing Add Transaction can call `load()` while the mutation bump also invokes a shell refresh.
- `CompassViewModel.addFunds` calls `onDataChanged` and then `reloadData()` itself.
- Transaction bulk/recurrence mutations call `onDataChanged` and `reload()` in the same task.
- Revisions or foreground events arriving during an existing fetch call `reload()` and start another task.

Impact:
The same full transaction/category/goal fetches and derived computations can run concurrently, multiplying cost at navigation and common mutation boundaries. Interleaving completions also waste work and can briefly publish results from an older request, although this audit did not reproduce stale UI.

Evidence:
- `InsightsView.swift:52-53` installs two appearance callbacks with identical effects; `PayCycleAwareModifier.swift:9` confirms the modifier calls its closure on appear.
- `CompassViewModel.load()` always creates a new unstructured task (`InsightsViewModel.swift:80-83`).
- A full Insights reload fetches transactions, goals, and categories and then recomputes all aggregates (`InsightsViewModel.swift:89-110`).
- `TransactionListViewModel.reload()` resets the guard and calls `load()` without handling `loadTask` (`TransactionListViewModel.swift:202-224`).
- Representative mutation paths call both the global callback and local reload (`TransactionListViewModel.swift:315-327, 825-847`; `InsightsViewModel.swift:154-168`).

Recommended Optimization:
Choose one refresh owner per event. Remove the duplicate Insights appearance trigger, make reload APIs coalescing/cancellable, and use a generation token before publishing results. Mutation methods should either refresh locally or emit a scoped invalidation, not both. Preserve a force-refresh operation for explicit retry and external-change cases.

Trade-offs:
Cancellation must not interrupt repository writes, only superseded reads/derivations. Coalescing can lose a required refresh if a mutation lands after the current fetch captured its snapshot, so the loader needs a dirty-while-loading state or serialized refresh loop rather than a simple `guard task == nil`.

Validation:
Instrument refresh start/end and repository fetch counts. Navigate to Insights once, dismiss Add Transaction after a save, fund a goal, bulk-edit Activity, and background/foreground rapidly. Assert one effective refresh per logical event, no concurrent analytical refreshes for the same model, and final state matching the latest repository contents.

Estimated Effort:
Medium

## PERF-112: Dashboard and Insights perform multi-pass full-history analytics on the main actor

Severity:
High

Confidence:
Strong Evidence

Category:
CPU | Concurrency | Rendering

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard/DashboardViewModel.swift`
- Lines: 14-15, 90-121
- Symbol: `DashboardViewModel.calculateMetrics()`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`
- Lines: 8-9, 89-110, 173-225, 252-260
- Symbol: `CompassViewModel.reloadData()` and compute helpers
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/ExplorerBreakdown.swift`
- Lines: 28-85
- Symbol: `ExplorerBreakdown.init`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/FinancialHealthService.swift`
- Lines: 6-71
- Symbol: `FinancialHealthService.compute`

Description:
Both view models are `@MainActor`. Dashboard detaches only its income/expense/recent pass, then synchronously runs Safe-to-Spend, habit templates/status, anomaly charting, budgets, and reminder checks on the main actor. Insights filters and repeatedly aggregates full transaction history on the main actor after fetching, including explorer, health, habits, hero, and averages.

Root Cause:
Pure snapshot analytics are invoked from main-actor-isolated methods and their `async` wrappers do not move CPU work to another executor. Insights' `async let` overlaps awaited I/O, but synchronous service calls still execute on the main actor. Several services independently scan the same history.

Trigger:
Initial loads, every global data revision, foreground refresh, pay-cycle changes, Insights navigation, and the duplicate/overlapping paths in PERF-110/PERF-111.

Impact:
At multi-year data sizes, each refresh performs many `O(n)` passes and allocations while the UI actor is responsible for input, navigation, and rendering. `FinancialHealthService` additionally scans expenses once per financial month and once per budget category. This creates a credible risk of navigation hitches and delayed interaction, amplified by redundant refreshes.

Evidence:
- `DashboardViewModel` is main-actor isolated; only lines 94-96 use `Task.detached`. Lines 101-120 immediately execute several full-history services after returning to the main actor.
- `CompassViewModel.reloadData()` assigns the full snapshots and calls all compute helpers before completion (`InsightsViewModel.swift:89-110`). Helpers such as `computeHeroInsight`, `refreshExplorer`, `computeHabits`, and `calculateAverages` contain no executor hop (`InsightsViewModel.swift:173-225, 252-260`).
- `ExplorerBreakdown` constructs three pie datasets plus period items from the complete transaction array (`ExplorerBreakdown.swift:37-75`).
- `FinancialHealthService.compute` repeatedly filters/reduces the six-month data and scans expenses once for each month and budgeted category (`FinancialHealthService.swift:17-67`).
- Existing forecast persistence is a real mitigation for forecast work, and Dashboard's first metrics pass is already detached; neither covers the remaining aggregates.

Recommended Optimization:
After measuring, create immutable `Sendable` inputs and compute a composite Dashboard/Insights aggregate off the main actor or inside the repository actor, then publish one result on `MainActor`. Reuse intermediate indexes/windowed subsets across services. Couple this with cancellation/generation checks so obsolete aggregates never publish.

Trade-offs:
Passing large arrays across executors may copy or retain snapshots and could offset gains. Consolidating services increases coupling; date, locale, currency, and user-default inputs must be captured consistently for one calculation. Swift concurrency/sendability constraints need explicit design, and small stores may not justify architectural work.

Validation:
Use Time Profiler plus points-of-interest signposts for each aggregate with 1k, 5k, and 20k transactions and realistic categories/goals. Exercise Dashboard launch, Insights navigation, period switching, add/edit, and foreground. Establish main-thread duration and frame-hitch baselines; compare after moving only measured hot computations. Run correctness tests against existing service outputs.

Estimated Effort:
Large

## Existing mitigations and rejected concerns

- `TransactionListViewModel` debounces text search by 250 ms and moves filtering/grouping to detached tasks; those are meaningful safeguards, though refresh coordination remains separate.
- Dashboard's `computeMetrics` already runs detached and uses a bounded top-five recent list rather than sorting the full store.
- Forecast computation has a persisted incremental cache; no claim was made that forecasting itself is a bottleneck.
- Observation uses `@Observable` and scoped child views rather than legacy `ObservableObject`; no blanket observation-framework migration is recommended.
- No memoization recommendation is based solely on a computed property. Each accepted finding has a concrete repeated traversal or duplicated refresh path and still requires runtime validation before implementation.
