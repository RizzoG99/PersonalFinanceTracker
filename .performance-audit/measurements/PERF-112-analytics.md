# PERF-112 / #236 — remaining Home and Insights analytics

## Scope and decision gate

Measured on 2026-10-16 in `.worktrees/performance-baselines`, branch
`chore/performance-baselines`, HEAD `eba7011` plus the existing WIP. All 43
pre-existing nonignored WIP file fingerprints were unchanged before updating
the audit handoff. The main checkout was not edited. No retired forecast-cache
implementation is used as evidence.

Investigation bound: a service baseline, one bounded intervention if justified,
and a comparable follow-up. There is no agreed product latency budget; the
harness does not assert a frame or tap-latency SLA. Simulator results justify
only the measured service decision, not a physical-device responsiveness claim.

## Method and provenance

- Xcode 27.0; macOS 27.0; arm64 iPhone 17 Simulator, iOS 27.0 (24A434),
  `pft-performance-baselines`, UDID `F160101A-8C10-4335-A155-D4156F027578`.
- Isolated `PersonalFinanceTraker-TEST` scheme/bundle, Debug-TEST (`-Onone`)
  and Release-TEST (optimized, `ENABLE_TESTABILITY=YES` for `@testable` access).
  Language/region `en_US`; timezone and actual clock are recorded per sample.
  Host load and thermal state were not controlled.
- A new in-memory SwiftData fixture uses `SampleData.populateModelContext()`,
  replaces sample transactions with exactly 5,000 fixed records, and supplies
  immutable snapshots through `MockTransactionRepository` to the **real**
  `DashboardViewModel` and `CompassViewModel`. Fixture construction, store
  fetch/mapping, global shell fan-out, gestures and SwiftUI layout are excluded.
  This deliberately isolates service work; it is not end-to-end navigation.
- Fixed ledger anchor `1791547200`, five-year span, one income per 20 records,
  integer-cent Decimal amounts, EUR and default categories, budgets on four
  categories. No recurrence rules, goals or travel. Unique fixture notes do not
  exercise populated quick-template results. A mutation sample substitutes a
  snapshot with an expense increased by EUR 123.45; it excludes persistence time.
- Home's injectable date is fixed at the anchor; other services retain their
  production wall-clock behavior. The ledger is deterministic; this is **not**
  a completely frozen-clock harness. Runs record clock/locale/timezone and
  reject crossing local midnight. Cross-date comparisons require renewed
  result parity. Calendar/pay-cycle edge cases have separate fixed-date tests.
- Pay-cycle day 1, then 27; Home buffer 10%; subscription score enabled;
  reminders disabled and prompt undismissed. TEST preferences and the previous
  habit-widget snapshot preference are restored. WidgetKit requests cannot be
  recalled. No personal ledger is seeded or modified.
- Each run emits 70 records: ten actions over a disabled parity round (-1),
  first instrumented round (0), and five warm rounds (1–5). Round 0 follows
  the parity round and is **not cold process/first-use evidence**. The table
  uses medians and min–max across rounds 1–5.

`PerformanceAuditRecorder.measure` wraps disjoint synchronous service calls.
It reads monotonic wall time and `CLOCK_THREAD_CPUTIME_ID` on the executing
thread, and records `isMainThread`. It never spans an await. CPU excludes the
scope's begin/end logging; the top-level action wall time includes instrumentation,
publication and await scheduling. Summed main CPU is the **covered services**,
not all main-thread CPU. The detached recent-selection scope is reported
separately. The async loader wall interval must not be interpreted as CPU time.
Only 4,096 synchronous samples are retained in memory; signposts remain complete.

## Before the bounded change

Release-TEST warm measurements, milliseconds:

| Action | Action wall median [min–max] | Covered main CPU median [min–max] |
| --- | ---: | ---: |
| Home initial load | 45.65 [43.69–46.31] | 41.41 [40.22–41.81] |
| Home return, guarded load | 0.17 [0.10–1.46] | 0 |
| Home pay-cycle reload | 47.42 [47.12–50.11] | 41.75 [41.54–42.18] |
| Home mutation reload | 45.56 [45.05–47.70] | 41.49 [41.19–42.39] |
| Insights navigation load seam | 12.97 [12.47–13.27] | 10.93 [10.44–11.18] |
| Insights previous month | 2.72 [2.58–2.98] | 2.37 [2.30–2.52] |
| Insights year | 13.30 [12.87–13.37] | 12.97 [12.58–13.02] |
| Insights week | 1.46 [1.39–1.56] | 1.18 [1.16–1.22] |
| Insights pay-cycle reload | 14.46 [14.03–15.47] | 10.95 [10.58–11.03] |
| Insights mutation reload | 13.32 [12.58–14.04] | 10.98 [10.58–11.22] |

The Debug baseline exaggerates some costs: Home initial covered main CPU is
69.94 ms and Insights 54.68 ms. Release is the relevant local comparison.

Largest initial Home service CPU medians in Release: daily logging 15.51 ms,
cycle summary 12.43 ms, reminder prompt 7.55 ms, daily check-in 3.17 ms.
Insights Health Score is 4.27 ms; the yearly explorer alone is 12.97 ms.
The corrected Daily Check-In formatter path is not the dominant remaining cost.

The selected hypothesis is that `CycleSummaryService` performs currency
conversion for all 5,000 records even though only the current and three earlier
cycles can contribute. Predict: gate conversion by the exact useful interval,
retain full-history first-recorded metadata, and reduce cycle-summary CPU while
preserving all outputs. Daily logging date derivation and repeated Health Score
windows were alternative hypotheses; they are not changed in this experiment.

## Red-capable regression and bounded correction

Before changing production code, the optimized `CycleSummaryServiceTests` run
executed 12 tests: 11 passed and one failed with
`currency.conversionCount == 6; currency.conversionCount → 9` in
`conversionWorkIsBoundedToRelevantCycles()`. The full expected `CycleSummary`
already matched. Local evidence: `.build/perf112-red.xcresult`.

The correction keeps the earliest-recorded date derived from **all history**,
then gates the amount-processing loop from the oldest eligible comparison
cycle through the current payday, end-exclusive. The existing per-cycle
conditions, Decimal arithmetic and input iteration order remain intact. Future
transactions within the current cycle still count in `out` and remain excluded
from pace until their date. No executor, await, cache or publication boundary
was introduced.

The additional fixed-calendar test covers pay-cycle day 27 across the Europe/Rome
DST switch, USD conversion, the next-cycle exclusive boundary, full-history
eligibility and future spending inside the current cycle. It checks cumulative
chart values, totals, usual pace and projection. The diagnostic harness also
checks that mutation reload updates actual spent totals and preserves the
selected Insights period. These are sequential freshness checks; the pre-existing
overlapping/unowned Insights reload issue (PERF-111) remains open. This synchronous
window change does not claim general latest-request/stale-commit protection.

## Comparable follow-up and stop decision

The optimized follow-up executed one test, passed with zero skips/failures, and
matched all **70** before/after records for recorded results, input/fetch counts,
service names and executing-thread coverage. The financial signature includes
Home income/spending and cycle income/out, check-in state, Insights score and
component scores, averages, recap totals, every explorer bar/date and category
amount. Complete Home cycle-summary fields, forecast and cumulative curve are
also asserted by the fixed-date regression tests; those are separate from the
recorded 5k signature.

Release-TEST CPU milliseconds, five warm repetitions per cell:

| Home action | Cycle summary before median [min–max] | After median [min–max] | Covered main CPU before → after |
| --- | ---: | ---: | ---: |
| Initial load | 12.43 [12.38–12.55] | 2.11 [2.07–2.34] | 41.41 → 30.11 |
| Pay-cycle reload | 12.56 [12.48–12.73] | 2.19 [2.11–2.45] | 41.75 → 30.01 |
| Mutation reload | 12.60 [12.46–12.80] | 2.31 [2.06–2.39] | 41.49 → 29.30 |

For initial Home load the targeted scope falls about **83%**, with disjoint
before/after ranges. Covered main CPU falls about 27%; top-level local wall
median is 45.65 → 33.54 ms. The conversion-count regression and the sharply
reduced targeted scope support the causal conclusion. Unchanged Insights work
also varies between runs (navigation covered CPU 10.93 → 10.01 ms), so its
small difference is **not attributed to the Home change**. Host load is an
uncontrolled limit; no physical-device latency or frame claim follows.

Compared instrumentation uses the same synchronous boundaries and clock reads.
Follow-up hardening adds a retention cap/error outcome in the recorder (neither
is hit by this harness), an explicit EUR preference matching the baseline, and
freshness assertions outside the timed interval. Fixture/input order and service
coverage remain identical. Clock epochs, configuration, HEAD/WIP and before/after
`CycleSummaryService` source hashes are retained in JSON provenance.

Artifacts: [Debug baseline](PERF-112-analytics-debug.json),
[Release before](PERF-112-analytics-release-before.json),
[Release after with parity result](PERF-112-analytics-release-after.json).
Local follow-up bundle: `.build/perf112-release-after.xcresult`.

Final verification: 63 targeted behavioral test cases passed (64 invocations,
including parameterized coverage), including both new cycle-summary regressions;
four recorder tests passed in a separate process. The optimized 5k benchmark
passed separately. `git diff --check` and Python syntax validation passed.
`graphify update .` completed and left Git status unchanged. Of the original
43 WIP files, 39 remain byte-identical; only summary, roadmap, validation plan
and manifest receive focused updates for this work, preserving unrelated WIP.

Stop at this bounded improvement. Daily logging/reminder date work remains
visible in Home; current Insights service measurements do not justify an
executor/cache redesign. Use the physical protocol below or a ledger with
material recurrence/goal/currency scale only if it changes the next decision.
PERF-112 remains partial for richer-ledger and overlap limits; the next independent
baseline is PERF-301. The later device run and user acceptance are recorded below.
Allocations, energy, light/dark, compact/wide layout, accessibility Dynamic Type
and VoiceOver were not checked.

## Device acceptance and commit authorization

After testing the updated app on the phone, the user reported that it feels
"parecchio fluido", accepted the fix and authorized committing it. This meets
the practical stopping criterion for the current scope. It is a user observation,
not a controlled physical-device before/after latency measurement.

After the user saved the Instruments document, the newly available **run 2**
was explicitly selected from `Activity-search-5k-PFT-TEST-iPhone-r1.trace`.
TOC: physical iPhone 14 Pro Max, iOS 27.0.1 (24A446), start
2026-10-16 10:15:32.939 +02:00, duration 115.973998 seconds, PID 29052.
The signpost subsystem is `rizzoG99.PersonalFinanceTraker.test`; recorded binary
UUID is `C877A110-907C-3418-8095-ECFE803938A4`. The intended scheme uses
Release-TEST, but the trace does not independently encode configuration name
or Git revision. Analysis checkout is `eba7011` plus preserved WIP.

The native tables contain 74 app intervals and 35 events. The ledger starts
at 5,000 and reaches 5,001 transactions after an add at about 59.7 seconds.
Thermal state is Nominal throughout. These are two observed Home reloads and
two Insights loads, not a repeated physical-device latency distribution.

| Recorded service/boundary | Exact trace interval (seconds) | Wall duration | Covered synchronous main CPU |
| --- | --- | ---: | ---: |
| Home metrics after pay-cycle setting | 31.189612–31.216837 | 27.22 ms | 25.63 ms |
| Cycle summary within that reload | 31.190396–31.191962 | 1.57 ms | 1.56 ms |
| Home metrics after mutation | 59.832777–59.922441 | 89.66 ms | 86.87 ms |
| Cycle summary within that reload | 59.834596–59.836391 | 1.79 ms | 1.79 ms |
| Insights load after mutation | 59.825930–60.065363 | 239.43 ms async wall | 9.37 ms |
| Later Insights load | 71.219849–71.281116 | 61.27 ms async wall | 8.21 ms |

The eight explorer scopes span 1.08–27.64 ms wall time; exact selected
granularities are not emitted in their metadata. Home's remaining mutation
CPU is led by daily logging (59.15 ms) and the reminder prompt (20.49 ms).
They were not changed. The 239 ms async Insights interval overlaps shell
fan-out and other work; it must not be called 239 ms of Insights CPU.

Time Profiler exports 16,380 samples, of which 13,013 main-thread samples
carry 13,013 ms of aggregate weight across the whole 116-second recording.
One main sample lacks a stack; all focused windows have complete stack/weight
coverage. The 59.6–60.2-second mutation window contains 406 ms of sampled
main work: nearest-app attribution includes fetch (71 ms), snapshot mapping
(36 ms), daily logging (59 ms) and reminder prompt (20 ms), alongside framework
work. These attribution rows are not self time or a freeze duration. Likewise,
`main` anchoring SwiftUI/UIKit stacks does not identify entry-point self cost.

The potential-hangs table flags one 253.41 ms microhang at 26.376144–26.629556
seconds. Its 26.1–26.9-second lead-in window contains 209 ms sampled main weight
with Profile construction, biometric/backup readiness, metadata and framework
update stacks. It does not overlap the Home/Insights analytics scopes and does
not establish a cycle-summary regression or a new actionable root cause.
There is no `Activity.filter` interval in this run; it is not a new search
key-to-result benchmark despite the filename.

[Redacted run-2 data](PERF-112-device-r2.json) retains native intervals, CPU
metadata, exact focused windows, counts and stack summaries. Raw XML/probes stay
ignored under `.build/perf112-device-run2-*`. No app/device/profiler was controlled.
The user observation and cheap measured cycle scopes support accepting this
bounded fix. No further structural optimization is scheduled; run 1 and run 2
are not equivalent before/after recordings and cannot establish a device speedup.

## Reproduction

Run the suite alone because instrumentation and app preferences are process-wide:

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_ANALYTICS_BASELINE=1 scripts/xcb test -configuration Release-TEST ENABLE_TESTABILITY=YES -only-testing:PersonalFinanceTrakerTests/AnalyticsBaselineTests -testLanguage en -testRegion US
rtk proxy xcrun xcresulttool export diagnostics --path .build/Test.xcresult --output-path .build/perf112-diagnostics-NEW
rtk python3 scripts/perf112_analytics_summary.py <exported-StandardOutputAndStandardError.txt> --output <measurement.json>
```

Require one executed/passed test, zero skips/failures, 70 complete records,
the expected service/fetch counts, and Decimal/chart/score parity. A successful
exit with a skipped or unbuilt test is not evidence. Initial compile failure
and an incorrectly forwarded opt-in (one skipped test) were discarded.

Saved local results: `.build/perf112-debug.xcresult`,
`.build/perf112-release-before.xcresult` and corresponding diagnostics.
Only fixed-fixture JSON records and distributions are retained in Git-visible
measurement files; raw diagnostics remain ignored.
Use `--compare <before.json>` with the summary script for the after run; it
rejects financial, count, locale/timezone and service/thread coverage differences.

## Physical-device gate

For a future responsiveness decision use the isolated PFT TEST app on the
representative iPhone 14 Pro Max, optimized Release-TEST, with the exact binary,
commit/WIP, OS, thermal state and the same fixture anchor recorded. Seed only
the disposable TEST store using the documented TEST-app setup, then remove
seeding arguments. Enable `-performanceAudit -performanceAuditScenario PERF112-5k`.
The user controls Instruments/device recording.

Record Time Profiler plus Points of Interest. Unlock normally, settle on Home
for ten seconds, open Insights and wait three seconds, select previous month,
year and week with three seconds between actions, return Home, change pay-cycle
day 1 to 27, then edit one synthetic expense by EUR 123.45. Wait five seconds
and save `.performance-audit/measurements/traces/PERF-112-device-r1.trace`,
explicitly noting run number and any visible stall. Repeat equivalent actions
for a distribution. The synchronous service scopes identify computation;
request-to-frame latency requires a verified pre-state-change interaction marker
and presentation evidence and is not supplied by an async load interval.
