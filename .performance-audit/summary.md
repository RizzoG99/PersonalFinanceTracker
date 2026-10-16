# Performance Audit Summary

## Publication checkpoint — 2026-10-16

PR #230 review corrections `8dbb9e4` are integrated. The isolated **PFT TEST**
variant is committed in `ce5cacb`: separate app/widget bundle IDs, App Group,
iCloud identifier and URL routing, with `PFT TEST` on the Home Screen. Both shared
schemes disable diagnostic arguments by default; onboarding/lock overrides,
seeding and receipt-photo export are not silently enabled. [Setup and exact
verification scope](../docs/development/test-app.md).

Fresh checks on the dedicated iPhone 17 / iOS 27.0 arm64 Simulator:

| Check | Result |
| --- | --- |
| Complete standard unit target | **827 passed, 0 failed, 15 skipped**; 897 passing executions |
| TEST identity/store, pending-intent, snapshot and search | **23 passed, 0 failed/skipped** |
| Isolated opt-in Activity 5k harness | **1 passed, 0 failed/skipped**; 24 unique samples with expected query/result/count coverage |
| Release-TEST build | Passed; actual compiler invocation uses `-O`; TEST app and both widget identities checked against generated Simulator entitlements |
| Disposable-simulator coexistence | 5,000 rows retained after relaunch without seed; TEST roots distinct; four normal-app store/WAL hashes unchanged |
| Profiling analyzer | **11 Python tests passed** |

The standard suite includes the new Activity harness as an explicit opt-in skip;
it executes separately above. These checks do not replace the original timing
samples or establish a fresh physical-device speedup. All historical measurement
JSON remains byte-identical. The original [integration report](measurements/PR-230-final-integration.md)
at `86bec05` retains its own source boundary; its Italian/UI/standard Release and
standalone recognizer results are historical, not new runs for this checkpoint.
No fresh iOS 26, hardware signing/iCloud/widget-tap, camera rotation, keyboard/frame,
iPad/wide, Dynamic Type or VoiceOver validation is claimed. Existing runtime and
compiler warnings documented by the historical reports are not declared resolved.

The remaining baseline reports and search harness are published together with this
status reconciliation. Raw traces/photos/stores and the local Xcode Cloud target
manifest remain excluded. Local evidence is under `.build/pr230-two-commits/` and
the isolated verification checkout; only curated historical reports are versioned.
Accepted optimization stops and OCR correctness follow-ups #244/#245 are unchanged.

## Historical receipt correctness follow-ups — 2026-10-16

Tracked separately in iOS Native (Todo / Analyzed): [#244 — tax selected as total](https://github.com/RizzoG99/PersonalFinanceTracker/issues/244)
and [#245 — wrong merchant, with accent-only cases distinguished](https://github.com/RizzoG99/PersonalFinanceTracker/issues/245).
Both include opaque fixture IDs/hashes, expected-versus-actual lookup, the already-executed
Release-TEST replay command and completion gates. Reproducibility currently requires the private
local corpus and the committed opt-in replay harness; these are Simulator replay findings, not demonstrated
physical-app errors. The final archived OCR xcresult was rechecked: one failed function, zero
skips; existing evidence records eight replays and six assertions. No new test run or fix here.
Raw images, labels and OCR remain ignored. PERF-301's accepted performance stop is unchanged.

## PERF-301 / #241 — user-accepted stop, 2026-10-16

[Recorded in GitHub #241](https://github.com/RizzoG99/PersonalFinanceTracker/issues/241#issuecomment-6218902824).

The user accepts the current production pipeline **under the verified conditions** and no
further optimization is scheduled. Historical iPhone 14 Pro Max use showed no perceived delay
despite measured main-thread crop work; final Release-TEST Simulator regression passes
122 functions / 148 executions, with restored crop/OCR-input pixels and actual OCR output
unchanged on 8/8 photos of one receipt. The separate strict OCR accuracy test remains red
with six existing assertions. The single-pass candidate was discarded because it changed
pixels and recognized lines on 1/8 inputs, despite synthetic CPU savings. This does not exclude
problems on other devices: older-device behavior, updated physical before/after, exact memory
peak/footprint and frame latency remain unverified. Reopen only for new evidence or a separately
authorized bounded experiment. [Acceptance, conditions and rejection reason](measurements/PERF-301-single-pass-experiment.md#user-acceptance--2026-10-16).
Status remains `BASELINE_MEASURED_STOP_IN_SCOPE`; other accepted stops and PERF-303 deferral stand.

## PERF-301 single-pass experiment — rejected, 2026-10-16

One user-authorized preventive experiment combined orientation/crop in one rendering on the
updated `e8df73f` base. Rotated valid-crop CPU falls 22–48% in the synthetic Simulator harness,
but crop and OCR-input pixel parity is **7/8** on the real corpus; the changed input also has
a different recognized line list. Key parsed fields retain the existing accuracy failures.
The candidate was **reverted**, restoring the exact original camera source. Final regression
passes **122 functions / 148 executions**, zero skips, including **8/8** restored crop/OCR pixel
comparisons. Keep the new regression oracle, summary tooling and evidence; no production
optimization is retained. [Report](measurements/PERF-301-single-pass-experiment.md) and
[redacted data](measurements/PERF-301-single-pass-experiment.json). No new broad device recording
for this rejected implementation. Other accepted stops and PERF-303/#237 deferral remain.

## Historical baseline worktree synchronization — 2026-10-16

Local merge **`e8df73f`** imports `origin/main` at `cc86f16`, retaining the existing performance
commits and WIP. Includes imported/localized category and rename fixes (#238/#240), plus scanner
rotation **#243 / #242**. Camera markers and fixture export retain the angle-mismatch full-frame
fallback. No rendering optimization or remote push. [Integration/validation record](measurements/PERF-301-main-sync.json)
and [receipt report](measurements/PERF-301-receipt-processing.md).
Targeted Release-TEST regression: **235 functions / 254 executions passed**, all 14 suites present,
zero failures; two language-gated skips were then exercised in the five-pass Italian category run.
Eight-photo replay remains red with identical outputs/six assertions; all eight crop JPEGs match
the pre-sync artifacts byte for byte. No new regression is inferred from these known failures.
Earlier receipt device numbers belong to the pre-rotation-fix build; no post-sync physical speed
or visual/rotation validation is claimed. Use the updated base for any subsequent experiment.
Accepted optimization stops and PERF-303/#237 deferral remain unchanged.

## PERF-301 supplied-photo correctness replay — 2026-10-16

Eight original iPhone photos and recorded quadrilaterals were recovered from the user's TEST
container and replayed twice through the actual crop/dual OCR/parser in Release-TEST Simulator.
Both runs executed one opt-in test, zero skips, all eight inputs; both **failed** with the same
six assertions: total matches **7/8**, date **8/8**, merchant exact **3/8** (four accent-only
differences, one incorrect merchant). The erroneous total selects tax although the correct total
is visible and recognized. Six uncropped diagnostic controls do not establish a safe bypass:
four totals are absent, including this input. Keep this red correctness baseline separate from
the user's satisfactory physical-device observation and from performance optimization.
[Redacted fixture evidence](measurements/PERF-301-device-fixtures.json) and
[full report](measurements/PERF-301-receipt-processing.md). Raw photos/labels/OCR/xcresults stay
ignored locally. **No processing optimization**; the rotation fix #243/#242 is now integrated as described above. Historical named corpora
are still missing; the new UUID corpus does not validate their skipped tests.

## PERF-301 memory observation — saved run 4

[Run-4 measurements](measurements/PERF-301-device-r4.json) verify three captures on iPhone 14
Pro Max / iOS 27.0.1, Release-TEST product path, Nominal thermal state. Crop wall is 222–252 ms
on main; OCR preparation is off-main. Native VM Tracker contributes 17 snapshots spaced about
3.8 s apart: highest observed resident **776.59 MiB**, dirty **352.56 MiB**; final dirty is
303.55 MiB and declining, above earlier 214–216 MiB plateaus. These are VM-region aggregates,
not physical footprint, exact transient peak or a leak diagnosis. Allocations was not recorded;
fixture export was still enabled. **Stop processing optimization under the accepted no-visible-
delay observation**; do not request another broad recording for a cleaner number. Reopen only
for a new stall, demonstrated sustained growth or pressure/termination. Exported local photos
now have the red correctness baseline above. Rotation fix #243/#242 is now integrated; physical retest remains unrun here.

## PERF-301 device observation — saved run 3

The user reports no noticeable slowdown or receipt OCR errors across full, distant, partial,
rotated and dim captures. [Run-3 evidence](measurements/PERF-301-device-r3.json) verifies physical
iPhone 14 Pro Max / iOS 27.0.1, Nominal thermal state. One capture has complete retained signposts:
**228.87 ms crop/orientation wall and 206.98 ms synchronous main-thread CPU**, with OCR preparation
off-main. Fixture export was active; this is not a clean transition-latency baseline or a
five-capture timing distribution. The numeric cost exists, but the agreed repeated-visible-delay
criterion is not met. **No processing optimization.** The later run-4 section above adds sampled native VM data;
physical footprint and exact transient peak remain unverified; local-photo replay failures are recorded above. The rotation UX
defect is tracked separately as [#242](https://github.com/RizzoG99/PersonalFinanceTracker/issues/242).
[Current receipt report and next steps](measurements/PERF-301-receipt-processing.md).

## PERF-301 / #241 baseline — 2026-10-16

[Focused receipt report and user-operated device protocol](measurements/PERF-301-receipt-processing.md)
and [synthetic Simulator summary](measurements/PERF-301-simulator-summary.json).
HEAD `3402878`, preserved performance-baselines WIP, PR #230 context. Opt-in instrumentation
separates camera wait/callback, synchronous orientation/crop, dismissal requests and OCR stages.
A 56-record Release-TEST synthetic transform baseline retains instrumentation-on/off pixel parity.
The actual async recognizer preparation executed off-main in its separate synthetic smoke run.
Validation: 117 receipt/form/geometry tests (128 executions), 17 category tests, four recorder
tests and the two isolated Release harness tests passed; three private-corpus/opt-in skips
remain explicit. Release-TEST build passed. 40/43 original WIP files remain byte-identical;
only summary/manifest/roadmap receive scoped updates. This synthetic run is not physical camera latency. The later run-3 follow-up above adds one
physical stage measurement; visible-frame latency and device peak footprint remain separate limits.
The subsequent eight-photo replay is red as described above. No image-processing optimization is made.
Stop before optimization pending repeated visible delay plus >=100 ms of attributed synchronous
main-thread image work, or separately observed memory pressure. PERF-201/PERF-112/PERF-111 stops
remain accepted; manifest/roadmap now reference the current #235 report. PERF-303/#237 stays deferred.

## PERF-111 / #235 follow-up — 2026-10-16

Insights reload ownership is mitigated in the verified ViewModel scope. Before
the fix, an older response overwrote a newer completed result in three repetitions
each at 1 and 5,000 transactions. A shared refresh task now coalesces pending
requests and publishes only the current generation, preserving selected periods,
late updates and retry after errors. An already-issued daily snapshot save keeps
the existing history policy. PERF-112 remains accepted in its existing scope.

Final targeted validation: 41 tests / 44 executions passed, zero failures/skips;
the optimized financial harness passed one test with 70 records. Historical
averages differ only by two fixture expenses leaving the rolling six-month
window; all other results/counts match. Physical/UI latency is unmeasured.
Stop structural work in this scope; #235 is not automatically closed by PR #230.
Original audit sections retain their historical snapshot.

Evidence: [ticket report](measurements/PERF-111-insights-overlap.md) and
[redacted validation](measurements/PERF-111-validation.json).

## Executive summary

Current status reviewed on **2026-10-16**, through review corrections `8dbb9e4` and the TEST/publication checkpoint above in `.worktrees/performance-baselines` (PR #230 context). The earlier merge `e8df73f` imports main `cc86f16`; historical receipt/integration sections retain their original source boundaries. Accepted PERF-111/#235 work remains attributable to `3402878`; earlier receipt device measurements retain their pre-merge provenance. Individual findings and original counts retain their historical evidence. This is a focused update, not a fresh audit of every remaining candidate. There are no P0 findings.

Refresh/cache, lifecycle, loader and Activity pagination changes have been implemented and behaviorally tested. The DateFormatter hot path was corrected. The user now reports a substantial improvement in search/filter use. Further Activity search/first-switch optimization is **deferred for now**, with mild typing lag still noted and no perceived freeze. This observation is not a controlled before/after latency measurement.

The new [physical-device search recording](measurements/Activity-search-5k-device-r1.md), run 1 on iPhone 14 Pro Max / iOS 27.0.1 with 5,000 transactions, has been analyzed. Seven filters take 24–61 ms off-main; grouped-state assignment stays below 0.54 ms. A typing window contains 369 ms of aggregate main-thread sampled weight over 1.2 seconds while no filter/group work runs. Input/SwiftUI list work is the next area to isolate only if the residual lag warrants it. Exact key-to-visible-result latency and an app-owned cause remain unproven. The old missing-run-3 request is superseded by this separate saved artifact.

**PERF-201 bulk edit/Undo baseline completed:** [results](measurements/PERF-201-baseline.md) confirm N saves, full 5k materializations, snapshot writes and WidgetKit requests for N selected rows. At 100 rows, local settled time is about 11.6 seconds per phase in Debug Simulator; this is not a physical-device latency result. The [batch follow-up](measurements/PERF-201-batch-followup.md) now performs one save/full materialization/widget request per phase: final-source 100-row medians are 215 ms edit and 204 ms Undo in Debug Simulator. Partial-failure, metadata, Undo and final widget checks pass; physical responsiveness is still unmeasured.

**PERF-112 service measurement completed for the 5k fixture:** [baseline and bounded follow-up](measurements/PERF-112-analytics.md) distinguish load, return navigation, period/pay-cycle changes and mutation reloads. In Release-TEST Simulator, covered main-thread service CPU is initially 41.41 ms for Home and 10.93 ms for Insights. One measured windowing change avoids currency conversion outside Home's current/three comparison cycles: cycle-summary CPU falls from 12.43 to 2.11 ms and Home's covered CPU to 30.11 ms. All 70 before/after result/count records match. Stop structural work in this scope; physical responsiveness and richer ledgers remain gates. Insights reload overlap is now mitigated separately under #235 / PERF-111. PERF-301 now has synthetic/device stage baselines, coarse VM samples and a red eight-photo Simulator correctness replay; exact frame latency/peak footprint and device-replay parity remain unverified.

## Current disposition

**PERF-111 / #235:** [current reproduction and bounded correction](measurements/PERF-111-insights-overlap.md) demonstrate an older Insights response overwriting a newer completed result, at both 1 and 5,000 transactions in three repetitions. One ViewModel refresh owner now coalesces pending requests and publishes only the current generation. Period/pay-cycle changes, late revisions, failures and foreground/external-write freshness have targeted behavioral coverage. Stop structural work in this scope; physical frequency and latency remain unmeasured. PERF-112 stays accepted in its existing scope.

| Root ID | Current status | What remains / decision |
| --- | --- | --- |
| PERF-110 | Mitigated in the implemented scope | Shared revision-aware snapshots, bootstrap/foreground gates and coalesced refreshes address measured duplication. Keep external-write freshness coverage; do not infer all lifecycle/iPad/device scenarios are closed. Residual first-switch work deferred. |
| PERF-111 | Mitigated in Insights reload scope | Shared ownership covers `load()` and awaited `reloadData()`; generation checks suppress obsolete publication and preserve pending follow-ups. A save already issued retains the existing daily-history policy. Physical latency and unrelated loader/goal CRUD ownership remain outside this verification. |
| PERF-112 | Partial; 5k service baseline and bounded correction completed | DateFormatter corrected; measured Home cycle-summary conversion window reduced CPU with result parity. No executor/cache redesign justified. Physical-device/richer-ledger validation remains. |
| PERF-101 | Mitigated in the implemented scope | Activity now computes one `activityPage` value per parent body, replacing the original twice-per-body grouped-category evaluation. Per-render scoping still exists; further caching has no demonstrated need. |
| PERF-303 | Partial; further performance work deferred | Canceled debounce sleep exits. Detached filter/group workers can still outlive their owners; filter publication has no latest-generation check. `clearSearch()` still schedules multiple derivations. Current device run does not prove stale results or cancellation correctness. |
| PERF-201 | Mitigated in bulk edit/Undo scope | Explicit batch boundary saves/refreshes once on success; failed batch saves retry rows independently before one final flush. 18 follow-up samples pass count/data budgets; note/amount/category, failure, metadata and Undo tests pass. Restore/recurrence, broad failure conditions and physical latency remain unmeasured. |
| PERF-301 / #241 | Baseline measured; single-pass trial rejected/reverted | Local rotated-crop CPU gain 22–48%, but real crop/OCR-input parity 7/8. Camera restored exactly; final 122 functions/148 executions pass with 8/8 restored parity. Existing accuracy failures remain separate. Rotation #243/#242 integrated. No retained optimization or post-change device claim. |
| PERF-100, PERF-202, PERF-205, PERF-300, PERF-302, PERF-305 | Awaiting focused baseline | Retain original candidates; recheck current reachability and representative inputs before optimizing. |
| PERF-102, PERF-400 | Low-priority measurement gates | Keep simple unless measured impact changes the decision. |
| PERF-203 | Resolved by PR #217 | Old forecast cache path removed; PERF-204 supporting evidence retired. |

Of the **15 retained, non-retired roots**, four are mitigated in scope, two are partial, eight await a focused baseline/gate, and one (PERF-301) has a bounded measured stop. These are disposition categories, not fifteen confirmed unresolved performance bugs. Original P1/P2/P3 priorities and confidence labels below describe the audited evidence; they do not override this current decision table. Evidence: [refresh/cache follow-up](measurements/Home-Activity-read-model-followup.md), [DateFormatter profile](measurements/PERF-112-daily-check-in-profile.md), [ViewModel baseline](measurements/Activity-search-5k-baseline.md), and [device search analysis](measurements/Activity-search-5k-device-r1.md).

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

### Historical disposition through `0c07a98` and initial measurement campaign

| Dimension | Count |
| --- | ---: |
| Active roots | 15 |
| High / P1 | 6 |
| Medium / P2 | 7 |
| Low / P3 | 2 |
| Confirmed | 2 |
| Strong Evidence | 10 |
| Potential | 3 |

The table above is retained as historical evidence accounting. Current work status is in **Current disposition**; the 15 retained IDs have not all been re-audited or fully resolved.

## Repository coverage

- Main app composition, authentication/lock lifecycle, iPhone and iPad shells, and first-load/foreground behavior.
- SwiftUI rendering and observation in Activity, Dashboard, Insights, iPad ledger, lists, tables, and Charts consumers.
- SwiftData repository access, snapshots, recurrence, forecasts, budgets, Safe-to-Spend, imports, exports, backup/restore, and widget refreshes.
- Receipt camera, AVFoundation session lifecycle, Vision/Core Image recognition, image memory, task cancellation, and concurrency boundaries.
- Widget and app-group snapshot call sites, Feature Discovery networking, relevant unit/UI coverage, and the existing coarse warm-launch test.

The original audit covered app-owned source and call sites, not third-party package internals. Later implementation and measurement evidence is linked separately; original report line references may be stale.

## Original finding priorities and evidence

### P0 — immediate

None. No issue has measured impact sufficient to justify P0.

### P1 — high-impact candidates

| Root ID | Finding | Confidence | Consolidated evidence |
| --- | --- | --- | --- |
| PERF-110 | Global revisions and lifecycle bootstrap fan out into repeated full refreshes | Confirmed | Five no-op foreground runs each produced 12 full fetches, two committed loads per feature, and duplicate snapshot/widget work |
| PERF-111 | Reload ownership permits duplicate and overlapping full refresh tasks | Confirmed | Two repeated 5k traces attributed separate `payCycleAware` and `onAppear` loads and observed overlap |
| PERF-112 | Dashboard and Insights run multi-pass history analytics on `MainActor` | Strong Evidence | Remains independently supported; PR #217 retired the PERF-204 forecast evidence |
| PERF-201 | Per-row/per-rule mutations repeatedly save, rebuild snapshots, and reload WidgetKit | Confirmed for bulk note edit/Undo | Real 5k baseline: N saves/full materializations/widget requests for N selected rows; restore/recurrence retain source evidence only |
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

## Next measurement priorities

These are measurement-gated options, not automatic implementation work. The current order is:

1. **PERF-201:** bulk edit/Undo batch implementation and comparable 1/10/100-row follow-up completed. Stop further structural work in this scope; assess actual use in PFT TEST before additional optimization. Restore/recurrence and physical responsiveness remain separate gates.
2. **PERF-112:** 5k service baseline and one comparable windowing correction completed. Stop here; use an optimized device recording or a materially richer ledger before further Home/Insights changes. Insights overlap is now separately mitigated in the #235 / PERF-111 ViewModel scope.
3. **PERF-301:** bounded baseline and one authorized preventive single-pass experiment completed. Trial rejected on real-image sampling preservation and reverted despite local CPU savings. No new generic trace for the rejected candidate. Further approaches require a new bounded decision; key-field accuracy issues remain separate and historical device VM limits still apply.
4. **PERF-302/PERF-305:** validate abandoned OCR work and the accuracy/latency trade of the second pass when investigating the receipt flow.
5. **PERF-202/PERF-205/PERF-100:** measure realistic recurrence, import and iPad rendering scale before indexing/caching.
6. **PERF-111/PERF-303:** Insights reload ownership is now mitigated in the #235 scope; Activity supersession correctness remains open. Do not reopen broad performance work merely because the historical findings remain listed.

PERF-110/PERF-101 mitigation and current Activity/search measurements do not justify another refresh architecture, dedicated SwiftData executor, debounce change or list rewrite. See [optimization roadmap](optimization-roadmap.md) for remaining gates.

## Historical architectural concerns and remaining limits

The following describe the original drivers. Shared snapshots and lifecycle/load gates now mitigate parts of items 1–3; a broad scoped-invalidation redesign is not the next task. Per-entity mutation side effects (item 5) were confirmed in the scoped PERF-201 baseline and are now coalesced for bulk edit/Undo; restore/recurrence still need separate measurement.

1. `DataChangedSignal` is global and untyped, so unrelated/hidden features refresh together.
2. `fetchAll()` is the common contract even for consumers needing a window, count, unordered input, or aggregate.
3. Refresh ownership is split across views, view models, mutations, lifecycle handlers, and widget updaters.
4. Several pure history-wide computations remain main-actor isolated.
5. Per-entity repository methods embed cross-cutting widget side effects, preventing efficient batch boundaries.
6. Some unstructured/detached tasks make the visible cancellation API ineffective.

## Disposition of the original quick wins

- Canceled debounce sleep now exits; `clearSearch()`'s multiple derivations remain unclosed.
- The duplicate Insights `onAppear` load was removed; #235 now adds measured, regression-tested ownership and supersession protection at the ViewModel boundary.
- The original duplicate grouped-category evaluation was replaced by one Activity page value per body. Repeated body evaluation per keystroke is a separate observation, not proof this small accessor is a bottleneck.

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

- The original audit had no physical-device profiling. A physical iPhone 14 Pro Max search run has now been analyzed; it is not a before/after comparison. Exact key-to-frame latency, memory graph, energy log, jetsam data and camera lifecycle remain unmeasured. Later PERF-301 device stage/VM observations and the red local-photo Simulator correctness replay are linked above; they do not establish a passing physical OCR accuracy benchmark.
- No current SwiftData query plan, migration benchmark, database-size distribution, or field telemetry.
- No build-time/compile-time audit, dependency-source audit, or third-party package internals.
- No production user dataset or import-size distribution.
- The original audit changed no production code. Later scoped fixes and the TEST variant are documented separately; this PERF-201 follow-up implements a scoped bulk edit/Undo batch boundary with regression tests and measurements.
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
- [Refresh/cache implementation and validation](measurements/Home-Activity-read-model-followup.md)
- [DateFormatter hot path](measurements/PERF-112-daily-check-in-profile.md)
- [Activity ViewModel 5k baseline](measurements/Activity-search-5k-baseline.md)
- [Physical-device search run 1](measurements/Activity-search-5k-device-r1.md)
- [PERF-201 bulk edit/Undo baseline](measurements/PERF-201-baseline.md)
- [PERF-201 batch implementation and comparable follow-up](measurements/PERF-201-batch-followup.md)
- [PERF-112 Home/Insights service baseline and bounded window follow-up](measurements/PERF-112-analytics.md)
- [PERF-111 Insights overlap reproduction and refresh ownership](measurements/PERF-111-insights-overlap.md)
- [PERF-301 receipt processing baseline and device protocol](measurements/PERF-301-receipt-processing.md)
- [Isolated TEST app and fixture setup](../docs/development/test-app.md)
- `optimization-roadmap.md`
- `validation-plan.md`
