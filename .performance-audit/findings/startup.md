# WS-STARTUP — Launch, Unlock, and Foreground Screening

## Scope and method

Static screening covered `PersonalFinanceTrakerApp`, `AppContainer`, `AuthenticationWrapper`, `AppShellModels`, the iPhone/iPad shell startup tasks, foreground handlers, first-screen loads, TipKit, notification setup, feature discovery, recurrence materialization, scheduled backup, and the existing UI launch test. Three findings were accepted. No launch metric, signpost trace, SwiftData trace, file-activity trace, or device profile was collected, so no finding is `Confirmed`.

## Phase separation

- **Cold launch:** `AppContainer.shared` is created synchronously before the scene, then a PIN-configured app mounts its shell and launches repository/widget maintenance behind the splash and lock overlay.
- **Warm unlock:** the shell and `AppShellModels` stay mounted across locking. Feature discovery is guarded to once per launch and begins only after PIN unlock plus splash dismissal. Unlock itself does not recreate the view models or rerun the shell's unkeyed startup task.
- **Foreground return:** `AuthenticationWrapper` performs cheap lock/grace decisions and starts scheduled backup, whose 24-hour freshness guard normally exits before fetching. On iPhone, `MainTabView` separately performs an unconditional data/materialization/widget refresh and then invalidates the same models again.

## Finding summary

| ID | Severity | Confidence | Phase | Title |
|---|---|---|---|---|
| PERF-400 | Medium | Strong Evidence | Cold launch | Persistence setup performs synchronous I/O before the first scene |
| PERF-401 | High | Strong Evidence | Cold launch / first unlock | Hidden shell bootstrap self-invalidates and repeats first-load work |
| PERF-402 | High | Strong Evidence | Foreground | iPhone foreground refresh reloads everything before and after its own revision bump |

Cross-workstream note: PERF-401 and PERF-402 are startup/foreground manifestations of the full-store-fetch fan-out recorded as PERF-200. Consolidation should preserve the phase-specific trigger evidence here while avoiding duplicate roadmap items.

## PERF-400: Persistence setup performs synchronous I/O before the first scene

Severity:
Medium

Confidence:
Strong Evidence

Category:
Startup

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`
- Lines: 20-32
- Symbol: `PersonalFinanceTrakerApp.init`, `sharedModelContainer`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift`
- Lines: 23-53, 88-134
- Symbol: `AppContainer.shared`, `seedDefaultCategoriesIfNeeded(in:)`, `hardenStore(at:)`

Description:
The app synchronously constructs the persistent `ModelContainer` before building its first scene. That path opens the SwiftData store, performs a category count query, may insert and save default categories, and executes file-attribute writes for the SQLite store and sidecars.

Root Cause:
The required container, data seeding, and file-protection hardening are combined in one static initializer referenced by an eager stored-property initializer.

Trigger:
Every process cold launch; the insert/save branch additionally runs for a new or wiped store.

Impact:
Store open/migration, the count query, and filesystem attribute calls are all on the pre-scene critical path, so any latency delays the first SwiftUI frame and splash. The actual cost and whether container creation dominates were not measured.

Evidence:
`sharedModelContainer` eagerly reads `AppContainer.shared`. The static initializer does not suspend: it constructs `ModelContainer`, calls a main-context `fetchCount`/possible `save`, then loops over three file URLs calling `setAttributes` before returning. This proves blocking launch work but not a user-visible regression.

Recommended Optimization:
First signpost container construction, category count/seed, and file hardening separately. Keep store availability as a required gate, but consider moving only independently safe post-open work off the first-frame path: avoid rewriting already-correct protection attributes, or defer/restructure reseeding with an explicit readiness contract if measurement shows it matters.

Trade-offs:
Default categories must exist before transaction entry, and weakening or racing file protection is unacceptable. Deferral adds readiness states and may cost more complexity than three attribute checks; retain the current design if profiling shows it is below budget.

Validation:
Measure cold launches on a fresh store, populated store, and migration-sized store with `XCTApplicationLaunchMetric`, `os_signpost`, SwiftData/Core Data instruments, and File Activity. Verify categories are available before first use and protection remains `.complete` for the store and sidecars.

Estimated Effort:
Medium

## PERF-401: Hidden shell bootstrap self-invalidates and repeats first-load work

Severity:
High

Confidence:
Strong Evidence

Category:
Startup

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/App/AuthenticationWrapper.swift`
- Lines: 143-166
- Symbol: `AuthenticationWrapper.body`
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift`
- Lines: 274-300, 335-347
- Symbol: `MainTabView.body` startup/revision tasks
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/iPad/IPadRootView.swift`
- Lines: 98-116
- Symbol: `IPadRootView.body` startup/revision tasks
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Plan/FixedExpensesSection.swift`
- Lines: 84-110
- Symbol: `CommittedSpendingModel.reload(repo:)`

Description:
For an existing PIN, the shell mounts behind the splash/lock before authentication and immediately preloads Activity, materializes recurrence, rebuilds two widget snapshots, and unconditionally bumps `DataChangedSignal`. That bump then reloads Dashboard, Activity, and Insights and rebuilds both snapshots again. On iPhone, the revision-keyed committed-spending task also runs once at revision zero and again after the bootstrap bump, fetching the full transaction/rule sets and rerunning detection.

Root Cause:
The global persisted-data revision is used as a bootstrap completion signal even when materialization made no mutation. Startup maintenance and first-screen loading are distributed across nested `.task`, screen `.task`/`onAppear`, and revision observers rather than coordinated as one bootstrap pass.

Trigger:
Cold launch with PIN setup complete, including while the user is still viewing the splash or lock overlay.

Impact:
Full-store fetches, derived calculations, recurrence detection, snapshot encoding/writes, and WidgetKit reload requests can execute twice and contend with authentication/first-screen readiness. Prewarming Activity also consumes work before the locked user can visit it.

Evidence:
`AuthenticationWrapper` explicitly documents that shell task/on-appear work runs behind the lock. Both shell startup tasks call Activity load, materialization, Habit/Safe-to-Spend refresh, then `dataChanged.bump()`. Their revision handlers immediately request the same view-model and snapshot work. `CommittedSpendingModel.reload` fetches all transactions/rules and performs detached recurrence detection for every revision. The recurrence service's in-flight guard prevents overlapping duplicate materialization, but it does not collapse the subsequent reload/snapshot fan-out.

Recommended Optimization:
Create one bootstrap coordinator with explicit outputs (`didMutatePersistence`, refreshed snapshot state, and readiness). Emit a global revision only when persistence actually changed, coalesce widget snapshot work, and load the visible first screen once after required maintenance. Keep Activity prewarming only if measurement demonstrates a worthwhile navigation benefit; otherwise defer it until unlock/idle or first visit.

Trade-offs:
Running maintenance early can make post-unlock data fresher and later Activity navigation faster. Reordering must preserve App Intent changes, recurrence correctness, widget freshness, deep-link consumption, and the security benefit of keeping the shell mounted.

Validation:
Add counters/signposts for bootstrap, `fetchAll`, each view-model load, committed-spending detection, widget snapshot writes, and revision bumps. Test cold launch with no due rules, due auto-record rules, forecast-only rules, and a multi-year ledger. Verify one settled load per consumer, correct first-visible data, and no unlock/deep-link regression.

Estimated Effort:
Large

## PERF-402: iPhone foreground refresh reloads everything before and after its own revision bump

Severity:
High

Confidence:
Strong Evidence

Category:
Startup

Location:
- File: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift`
- Lines: 274-282, 294-300, 304-334
- Symbol: `MainTabView.body` scene-phase and revision handlers
- File: `PersonalFinanceTraker/PersonalFinanceTraker/App/AuthenticationWrapper.swift`
- Lines: 268-329
- Symbol: `AuthenticationWrapper.body` foreground/authentication handling

Description:
Every iPhone transition to `.active` first reloads Dashboard, Activity, and Insights. It then materializes recurrence, refreshes both widget snapshots, and unconditionally bumps the global revision. The revision observer reloads all three models and refreshes both snapshots a second time; the revision-keyed fixed-expense detector also runs again.

Root Cause:
The foreground pipeline both performs refresh work directly and broadcasts a global invalidation afterward without tracking whether recurrence materialization changed persisted data.

Trigger:
Return the iPhone app from background, including a return that requires PIN/biometric authentication.

Impact:
Warm resume pays repeated full-store fetch/sort, derived-model calculations, snapshot serialization, and widget timeline reloads while authentication and the return animation are in progress. The duplicate work scales with ledger size and is reachable on a common lifecycle event.

Evidence:
At `.active`, lines 308-318 invoke all three reloads, both snapshot refreshes, and `dataChanged.bump()`. Lines 274-281 observe that bump and invoke all three reloads plus both snapshot refreshes again. `AuthenticationWrapper` starts scheduled backup at the same `.active` transition, although its 24-hour guard usually exits cheaply. This is definite duplicate scheduling; actual resume latency is unmeasured. `IPadRootView` has no equivalent scene-phase refresh, so this finding is iPhone-specific.

Recommended Optimization:
Run materialization first, have it report whether it mutated data, then execute one coalesced refresh plan. Refresh consumers once for external/App Intent changes and emit a revision only when another observer genuinely needs it. Deduplicate Habit/Safe-to-Spend generation into one foreground snapshot update.

Trade-offs:
The app must still notice App Intent writes made while backgrounded, even when materialization is a no-op. A repository revision token, persisted change marker, or explicit foreground reason is safer than simply removing reloads.

Validation:
Instrument foreground-to-interactive time and count repository fetches, model reloads, revision bumps, snapshot writes, and WidgetKit reload calls. Test no external change, App Intent quick-add, due recurrence, grace-period unlock, expired-grace biometric unlock, and long-stale backup. Confirm each consumer settles once with current data.

Estimated Effort:
Medium

## Existing guards and screened paths without an accepted finding

- `AppShellModels` is constructed once by `AuthenticationWrapper`; its initializers are lightweight and shared instances survive lock/unlock.
- `didPrepareFeatureDiscovery` prevents repeat network loads across unlocks. Its task starts only after PIN unlock and splash dismissal, and WS-DATA found no evidence justifying a cache-policy change.
- `RecurrenceMaterializationService` shares an in-flight task, preventing overlapping launch/foreground calls from double-inserting. It intentionally does not become a once-per-session no-op.
- `BackupScheduler` exits from a `UserDefaults` timestamp when the last backup is under 24 hours old. A stale backup can contend with foreground refresh, but its daily frequency and cost are not sufficient for a separate static finding.
- TipKit configuration, notification-delegate assignment, appearance setup, and the member-since default are synchronous, but no concrete repeated expensive pattern was found beyond the accepted candidates above.
- Reminder rescheduling creates at most seven one-shot requests on active/background transitions. No evidence established it as a material launch or resume cost.

## Launch-test coverage and evidence limitations

- `PersonalFinanceTrakerUITests.swift` lines 39-97 measure the median of three simulator **warm** launches after an unmeasured warm-up. They intentionally disable PIN setup, onboarding, and tips; they do not cover fresh-store cold launch, locked launch/first unlock, or foreground resume.
- The test times `XCUIApplication.launch()` externally, including XCUITest termination, idle waiting, and simulator overhead, and uses a deliberately loose 25-second regression budget. Its own documentation says it catches only multi-fold regressions, not subtle startup changes.
- The current test avoids `XCTApplicationLaunchMetric` because per-worktree simulator UUIDs make stored baselines ineffective. That operational constraint is valid, but it leaves no app-only cold/warm metric in the checked-in suite.
- No device-specific baseline, signposted phase breakdown, SwiftData migration fixture, large-ledger launch fixture, or foreground-to-interactive benchmark exists. All accepted findings therefore require focused measurement before implementation.
