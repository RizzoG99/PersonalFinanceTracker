# Independent Validation: Startup Findings

## Verdict summary

This review challenged PERF-400, PERF-401, and PERF-402 against the cold-launch, locked-shell, unlock, and foreground call chains. No launch metric, device profile, SwiftData trace, or foreground-to-interactive measurement was available.

| ID | Verdict | Validated severity | Confidence | Priority |
| --- | --- | --- | --- | --- |
| PERF-400 | Downgrade | Low | Potential | P3 |
| PERF-401 | Keep | High | Strong Evidence | P1 |
| PERF-402 | Keep | High | Strong Evidence | P1 |

No finding is `Confirmed`; no P0 is justified.

## PERF-400 — Downgrade to Low, Potential, P3

Reachability is correct. `PersonalFinanceTrakerApp.sharedModelContainer` eagerly reads `AppContainer.shared` before the first scene (`PersonalFinanceTrakerApp.swift:20-32`). The static initializer synchronously opens the SwiftData container, performs a category `fetchCount` and possible first-run save, then calls `setAttributes` for the store and two sidecars (`AppContainer.swift:23-53, 88-134`). This executes on every process cold launch, while category insertion is correctly limited to an empty store.

The original severity/confidence overstates what static evidence proves. Opening the model container is a required readiness gate, not an avoidable defect. On a populated store, the additional app-owned work is one count query and at most three small filesystem attribute calls. There is no evidence that these operations materially delay the first frame, nor that checking before setting protection would be cheaper. Fresh-store seeding is infrequent and required before transaction entry.

Keep this as a P3 measurement hypothesis, not an optimization commitment. Measure container open/migration, count/seed, and hardening separately. Only defer or conditionalize the latter two if their inclusive cold-launch cost is material and category/file-protection readiness remains explicit.

Correction: confidence should be `Potential`; the code proves synchronous I/O on the critical path, not a concrete expensive or user-visible bottleneck.

## PERF-401 — Keep High, Strong Evidence, P1; consolidate

The locked cold-launch path is reachable and unconditional for an existing PIN. `AuthenticationWrapper` mounts the iPhone/iPad shell whenever `isPINSetup` is true, even while splash/lock UI covers it (`AuthenticationWrapper.swift:129-166`). It constructs `AppShellModels` once and does not rebuild them at unlock (`AuthenticationWrapper.swift:28-46`).

The shell startup task then loads Activity, materializes recurrence, refreshes Habit and Safe-to-Spend snapshots, and unconditionally bumps `DataChangedSignal` (`MainTabView.swift:335-342`; `IPadRootView.swift:107-115`). The bump immediately reloads Dashboard, Activity, and Insights and repeats both snapshot refreshes (`MainTabView.swift:274-281`; `IPadRootView.swift:98-105`). On iPhone, `.task(id: dataChanged.revision)` runs initially at revision zero and again after the bump, so committed-spending performs two full-history/rule passes (`MainTabView.swift:292-300`; `FixedExpensesSection.swift:84-110`). Dashboard/Activity load guards do not help because the revision path calls `reload()`, and Insights has no coalescing guard. Materialization's `inFlight` guard prevents duplicate overlapping materialization only; it does not suppress the reload/snapshot fan-out (`RecurrenceMaterializationService.swift:7-25`).

High/P1 is justified as structural duplicate startup work scaling with the full ledger. Work occurring behind the lock may sometimes prewarm data before unlock, but it can also contend with first-interactive readiness; measurement must decide whether Activity prewarming is beneficial.

Deduplication: PERF-401 is not a separate root cause from PERF-110/PERF-200. Consolidate it into the global refresh-amplification roadmap item as the cold-launch/locked validation scenario, retaining its revision-zero committed-spending evidence.

Correction: “first unlock” is not a second trigger. The shell bootstrap begins at cold mount before authentication and does not rerun merely because the user unlocks.

## PERF-402 — Keep High, Strong Evidence, P1; consolidate

The duplicate iPhone `.active` sequence is definite. Before its asynchronous maintenance completes, `MainTabView` immediately calls all three feature reloads (`MainTabView.swift:304-312`). It then materializes recurrence, refreshes Habit and Safe-to-Spend snapshots, and unconditionally bumps the revision (`MainTabView.swift:313-318`). That bump invokes the revision handler, which reloads the same three models and refreshes the same two snapshots again (`MainTabView.swift:274-281`); it also reruns committed-spending through the revision-keyed task (`MainTabView.swift:292-300`).

This happens on an ordinary background return and can also occur on other transitions to `.active`; it is not conditioned on persistence having changed. `AuthenticationWrapper` may start scheduled backup at the same transition, but its separate 24-hour guard means backup is not evidence for this finding (`AuthenticationWrapper.swift:281-328`). iPad has no equivalent scene-phase pipeline.

High/P1 is justified because warm resume is frequent and the duplicate full-store/snapshot work is scheduled while the user is returning to interaction. Runtime latency remains unmeasured. Materialization should run first and report mutation state, but an external-change marker/repository revision is required so App Intent changes are not missed when materialization is a no-op.

Deduplication: PERF-402 is the foreground manifestation of PERF-110/PERF-200 and overlaps PERF-111's uncoalesced loaders. It should be a required resume scenario and acceptance test under the same roadmap item, not a third implementation issue.

## Consolidated validation plan

1. Instrument one shared refresh-amplification initiative: repository full fetches, feature reload starts/commits, revision bumps, snapshot writes, and WidgetKit reload requests.
2. Measure separately: locked cold launch with no due rules, locked launch with due rules, first unlock while bootstrap is still running, no-change iPhone resume, App Intent mutation, and due recurrence.
3. Require one settled refresh per consumer without stale first-visible data; preserve iPad behavior and verify deferred off-screen loads remain current when first opened.
4. Profile PERF-400 independently so required container-open time is not misattributed to optional seeding/hardening work.
