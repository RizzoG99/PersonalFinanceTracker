# Home → Activity follow-up — 2026-10-12

> Publication note — 2026-10-16: Historical implementation and measurement log. The source revisions, workflow statements and test totals below describe those individual runs. Current PR publication/integration status is recorded in [the summary](../summary.md); this report does not claim a fresh physical before/after comparison.

Status: scoped correctness/refresh fixes ready for review; residual first-presentation optimization deferred pending a disruptive daily-use device observation.

Current index update — 2026-10-15: the missing search-run request described later in this historical note is superseded by [a separate physical-device search trace, run 1](Activity-search-5k-device-r1.md). The user reports substantial overall improvement and mild typing lag without freeze; further Activity/search optimization is deferred for now. See [current disposition](../summary.md) and [next measurement roadmap](../optimization-roadmap.md); PERF-201 is planned and not started. The historical results and original capture limitations below are preserved.
Worktree: `.worktrees/performance-baselines`, branch `chore/performance-baselines`, base HEAD `390b1fc`.
All pre-existing WIP was preserved. No reset, checkout, stash, clean, rollback, or commit was performed.

## Evidence and limits of attribution

The retained `traces/PERF-110-device-manual-save-r5.trace` TOC identifies an iPhone 17
**simulator**, iOS 27.0, scenario `activity-pagination-5k-r1`. Its filename does not
establish a physical-device provenance. Only the existing recording was exported;
no profiler or interactive simulator session was controlled.

- `Activity.tab.selected`: 25.156490791 s.
- Immediately following: two `Activity.load.request` events, each followed by
  `Activity.load.skipped`; no post-selection load or repository fetch.
- Selection window 25.156490791–26.200000000 s: 263 main-thread CPU samples,
  each weighted 1 ms, hence 263 ms aggregate sampled weight.
- 48 ms of leaf weight is in `swift_conformsToProtocolMaybeInstantiateSuperclasses`.
  Its callers include SwiftUI `DynamicPropertyCache.fields`, view-list/modifier
  construction, and collection-list cell sizing. These are first-presentation costs.
- 256 ms has `$main()` as the nearest app frame. This **does not** attribute that work
  to the app entry-point body; most work is inside framework/runtime frames.
- No named TransactionActor, TransactionSnapshot, ActivityView, ActivityRow, or
  TransactionListViewModel frame was found in that selected window. This limits
  app-owned attribution and does not prove absence of inlined/unsymbolicated work.

Thus this recording excludes a fetch triggered by the tap as the cause of its
residual cost. It supports testing smaller concrete SwiftUI type boundaries.
It does not justify a new SwiftData executor, prove the device's exact cause, or
establish that the component extraction improves latency. Those conclusions require
a comparable follow-up recording. The executor was not changed.

## Demonstrated cache regression and fix

Before changing cache behavior, `scripts/xcb test
-only-testing:PersonalFinanceTrakerTests/TransactionActorCacheTests` ran five tests:
four failed and one passed. Two failures reproduced stale values at the real repository seam:

- A warmed reader missed `Intent write` saved by a second TransactionActor.
- A direct ModelContext save left the reader's note at `Before`, rather than `After`;
  related category icon/color and deletion assertions also exposed stale snapshots.

The other two failures were pre-existing global recorder-count assertions contaminated
by the instrumented app host's own work. They now assert the test actor's materialization
generation, so their oracle does not count other repositories in the host process.
The failed run also spent 600 seconds attempting to collect simulator diagnostics;
that delay is a test infrastructure issue, not an Activity timing measurement.

The read cache now carries a container-scoped revision. A synchronous `ModelContext.didSave`
observer advances it for transaction/category changes, including direct writers and distinct
actors. Health-score/unrelated saves with identifier details, and other containers, do not
invalidate it. Missing save details conservatively invalidate the container. Explicit
invalidation advances the revision for all its readers. Cache misses materialize immutable
snapshots in a fresh actor-confined read context and retry if the revision changes during
materialization. No live SwiftData model/context crosses an actor boundary.

A genuine background return performs one shared, awaited invalidation before shell or backup
reads, covering writes for which this process receives no notification. Backup now uses the
shell repository and its cache rather than constructing another repository at every activation.
The existing bootstrap gate still controls launch maintenance; Activity load completion now
includes date/travel grouping. iPad receives the same guarded foreground preparation and
awaits the Activity preload in bootstrap.

Activity discards a read superseded by a pending reload before publishing it, retries failed
initial loads, and retains the coalesced follow-up load. The first page remains 200 rows and
full-data search, filters, totals, grouping and selection semantics remain intact.

## Files changed in this follow-up

Paths under `PersonalFinanceTraker/PersonalFinanceTraker/`:

- `Models/TransactionActor.swift`
- `Models/TransactionSnapshotRevision.swift` (new)
- `App/AppShellModels.swift`
- `App/AuthenticationWrapper.swift`
- `Features/MainTabView/MainTabView.swift`
- `Features/iPad/IPadRootView.swift`
- `Features/TransactionListView/ActivityView.swift`
- `Features/TransactionListView/Components/ActivityListSections.swift` (new)
- `Features/TransactionListView/TransactionListViewModel.swift`
- `Utilities/PerformanceAuditRecorder.swift` (continued existing untracked WIP)

Paths under `PersonalFinanceTraker/PersonalFinanceTrakerTests/`:

- `Models/TransactionActorCacheTests.swift` (continued existing untracked WIP)
- `Features/TransactionListView/TransactionListViewModelTests.swift`
- `Mocks/MockTransactionRepository.swift`

This measurement note is the only audit-document addition from the follow-up; the existing
dirty findings, manifest, summaries, configuration and localization changes were preserved.

## Validation

- `rtk scripts/xcb build`: passed, including the final build after foreground changes.
- Initial post-fix cache + Activity run: 57 passed, zero failed.
- Extended run: **108 passed, zero failed, zero skipped**, confirmed by the JSON summary.
  Suites: TransactionActorCacheTests, TransactionListViewModelTests, SearchTests,
  TravelGroupingTests, TravelListRefreshTests, TravelRepositoryTests,
  BootstrapMaintenanceGateTests, ForegroundRefreshGateTests,
  PerformanceAuditRecorderTests, BackupSchedulerTests, BackupServiceTests.
- Final cache-only run: **10 passed, zero failed**, including additional assertions that
  directly deleting a category clears cached category ID, icon and color metadata.
- Covered real second-actor saves, direct-context edits/deletion and category metadata,
  batch/update/delete/travel/recurrence mutations, cache retention after unrelated saves,
  shared foreground invalidation, a separate disk-backed container representing an external
  writer, and a controlled data revision while an Activity read is suspended.
- `TransactionSnapshotRevision.swift`: standalone Swift 6 strict-concurrency typecheck passed.
- The checked-in target settings are `SWIFT_VERSION = 5.0`. A command-line Swift 6 override
  fails in ZIPFoundation on mutable globals `maxUInt32`/`maxUInt16` before proving whole-app
  Swift 6 compatibility. No project setting or dependency source was changed. The normal
  build also reports existing concurrency warnings in ReceiptCameraView.
- `graphify update .`: completed; before/after Git status was identical.
- `git diff --check`: passed.

Static UI review compared Activity's existing TransactionItemView/TravelRowView, Dashboard,
and DesignTokens. The extracted components preserve surfaces, spacing, colors, privacy,
selected traits, long-press behavior, destructive dialogs, localization keys and 44-point
pagination action. The existing SampleData preview remains available. Visual execution of
light/dark, compact/wide, accessibility Dynamic Type, VoiceOver, loading/empty/populated and
destructive interactions was **not** performed; these remain manual checks.

## Exact next profiling protocol

Use the physical device and existing real 5,000-transaction store. Do not reseed or add
transactions for this switch-only scenario. Use one comparable build configuration and
record device model, OS, transaction count, thermal state, and whether Instruments was
attached at launch. Record **Time Profiler + Points of Interest** together; do not use Hitches.

Launch arguments (retain the existing values):

```text
-performanceAudit
-hideTips
-feature_discovery_has_completed_tour YES
-performanceAuditScenario PERF-110-device-manual-save-r5
-performanceAuditAnchorEpoch 1791547200
-performanceAuditSkipLock
```

The existing skip-lock flag is DEBUG-only. For a Release/Profile build, manually unlock if
required and record that step; do not interpret lock/authentication time as tab-selection cost.

1. Begin a fresh recording at launch. Remain on Home approximately 10 seconds.
2. Tap Activity exactly once, leave it untouched for another 5 seconds, then stop.
3. In Points of Interest, select `Activity.tab.selected`. It is now a real signpost event
   as well as a PFT_PERF log. Retain the full trace, not only screenshots.
4. Inspect two exact windows from that marker: `[tap, tap + 1 s]` and `[tap, tap + 5 s]`.
   Filter Time Profiler to the app's Main Thread. Export the expanded call tree with weight
   and self weight, showing framework and app frames; also inspect the inverted tree.
5. Record post-marker loader/fetch counts and overlap with Habit, SafeToSpend and backup work.
   A settled preload should produce skipped load requests at selection and no new store read.
6. Compare the following intervals/events:

| Marker | What it measures |
| --- | --- |
| `Activity.view.body` | Synchronous evaluation of the parent SwiftUI body; not layout or a frame |
| `Activity.page.prepare` | Preparation of the current date/category page |
| `Activity.derivedFilters` | MainActor category chips/icons and filtered totals |
| `Activity.filter` / `Activity.group` | Detached search/filter and date/travel grouping work |
| `Activity.group.publish` | Publication of grouped rows on MainActor |
| `Activity.list.appeared` | List lifecycle appearance and row/group counts; **not a first-frame marker** |
| `TransactionActor.store.fetch` | Synchronous SwiftData fetch |
| `TransactionActor.snapshots.map` | Synchronous model-to-snapshot conversion, including lazy faults |
| `TransactionActor.fetchAll` | Cache/store source, revision and actor-local materialization generation |
| `Lifecycle.foreground.snapshots.invalidated` | Shared invalidation before foreground readers |

Begin/end/event messages include `main=true/false`; synchronous fetch/map intervals have
no suspension inside them, making their thread association meaningful. An async loader's
begin/end thread still does not imply it consumed its entire interval there.

Repeat at least three equivalent fresh launches, saving separate trace files without
overwriting the baseline. Use the same instrumentation/settings in both compared builds.
Report all per-run main-thread weights, named hot stacks, loader/store-read counts and the
observed freeze; do not call a lower wall-time loader interval alone a responsiveness fix.

Then verify freshness separately: save/edit a transaction, change a category icon/color,
perform an App Intent save and foreground, and check Activity, Home, widgets and backup.
Exercise search, structured filters, travel collapse/expand, long-press selection,
recurring/travel delete confirmations and Show More. Include light/dark, compact/wide,
accessibility Dynamic Type and VoiceOver checks.

Remaining decision: retain/adjust the SwiftUI extraction based on measured first-presentation
cost. Consider a dedicated SwiftData executor only if the new synchronous fetch/map markers
and CPU stacks show materialization on the main thread inside the measured critical path.

## 2026-10-15 follow-up and shipping decision

Run 2 of the same saved trace was recorded at 10:18 local time on the same iPhone 17
simulator, iOS 27.0. It contains the new markers and a 5,000-transaction preload. The
first Activity body starts at 33.531235291 s, but `Activity.tab.selected` is emitted only
at 34.005797 s. The latter comes from a TabView onChange callback and is **not** an
accurate request/tap boundary. The nominal post-marker protocol above must include the
earlier body/CPU work, or use an earlier request marker in a future capture.

| Main-thread sampled weight | Run 1 | Run 2 |
| --- | ---: | ---: |
| Half-second before the selection marker | 260 ms | 259 ms |
| One second after the marker | 263 ms | 258 ms |
| Combined 1.5-second window | 523 ms | 517 ms |
| Five seconds after the marker | 287 ms | 291 ms |

These two simulator runs do not establish a meaningful first-switch improvement from the
component extraction. Run 2 includes 180 ms leaf weight in Swift protocol-conformance
resolution and 79 ms inclusive weight in collection-list cell sizing in the combined
window; these overlapping categories must not be added as a freeze duration. The first
parent body interval is 4.041 ms and page preparation is 0.331 ms.

The initial synchronous store fetch (80.539 ms) and mapping (65.617 ms) both run on the main
thread and finish at 6.726 s. This confirms the construction/execution concern for bootstrap,
but it is outside the later switch. Subsequent reads are cache hits. Both post-selection
load requests are skipped; no load/fetch/widget/maintenance interval overlaps the switch.

Decision agreed with the user: ship the verified cache, coalescing, lifecycle and pagination
improvements; stop further structural first-switch refactoring for now. Resume only if
optimized physical-device daily use still exposes a disruptive freeze. No dedicated
SwiftData executor or artificial delay was introduced.

### Search request and reusable workflow

The user requested analysis of search in the final ten seconds of **run 3**. At inspection,
the saved trace contains only runs 1 and 2. Run 3 must be saved into that document or supplied
as another file before a search-performance verdict is possible. The final ten seconds of
run 2 contain Activity entry, not the requested search experiment; they cannot substitute
for the missing recording. Search correctness is covered by tests; typing-to-result latency
remains unverified.

The new project-local `performance-profiling` skill documents interaction boundaries,
device capture, explicit run selection, sample/interval interpretation and stopping criteria.
Its stdlib extractor has 11 passing parser/window tests, passes the skill validator, and
reproduces run 2's 517 ms combined-window result. Independent forward-testing also confirmed
the absent-run refusal, delayed-marker interpretation and missing search-latency evidence.
The helper preserves begin/end metadata, reports missing CPU exports distinctly from idle
windows, and retains the actionable prefix of export failures.

Before PR publication, the two new pagination strings were completed in English/Italian,
and destructive fixture seeding was compile-gated to Debug simulator builds. Local Xcode
project reordering, audit launch arguments in the shared scheme, and Xcode Cloud staging
files remain outside the PR. Raw traces/logs remain ignored.
