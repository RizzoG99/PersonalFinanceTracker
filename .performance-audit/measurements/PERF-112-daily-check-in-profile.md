# PERF-112 follow-up — Daily Check-In date-key hot path

> Publication note — 2026-10-16: Historical date-key profile and implementation log. The correction is integrated; the later bounded cycle-summary experiment and accepted device observations are documented in [PERF-112-analytics.md](PERF-112-analytics.md). Original timings and workflow statements below retain their historical scope.

Status: `CONFIRMED` for this measured hot path

## Scenario

On 2026-10-11, a 5,000-transaction simulator fixture was profiled with Time
Profiler while reproducing the first Home-to-Activity navigation. The user
waited on Home before selecting Activity, so the already-resolved Activity
loader was not attributed to the tap.

## Measured result before the correction

The Main Thread call tree recorded:

| Symbol | Inclusive / self weight |
| --- | ---: |
| `DailyCheckInService.dateKey(for:calendar:)` | 4.50 s / 4.49 s (45.0%) |
| `TransactionActor.fetchAll()` | 1.25 s / 660 ms (12.5%) |
| `PersonalFinanceTrakerApp.$main()` | 889 ms / 824 ms (8.9%) |

`DailyCheckInService.computeStatus` maps every transaction to a date key.
Before the correction, `dateKey` allocated and configured a new
`DateFormatter` for every call. The 5,000-record fixture therefore repeatedly
created locale/calendar formatter state on the UI actor. This directly
explains the observed multi-second interaction stall; it is not a claim about
device energy or release-build latency.

## Correction under validation

`DailyCheckInService.dateKey` now derives year/month/day once through the
provided `Calendar` and builds the stable persisted `yyyy-MM-dd` key directly.
The behaviour-preserving timezone regression test passes. The full test-build
and the six `DailyCheckInServiceTests` also pass. A repeat Time Profiler run
on the same 5,000-record scenario is still required to quantify the reduction.

## Follow-up: duplicate initial foreground plan

The first run after the date-key correction no longer listed `dateKey` among
the measurable hot symbols; `DashboardViewModel.refreshDailyCheckInState()`
accounted for 47 ms. The same run retained a distinct structural problem:
bootstrap started two sequential Activity intervals, `515.9 ms` and
`1.206 s`, and completed 11 `TransactionActor.fetchAll` intervals between
`00:09.007` and `00:12.723`.

The iPhone shell's `.active` handler scheduled Dashboard, Activity, and
Insights refreshes while its bootstrap task was already performing the first
load plan. `ForegroundRefreshGate` now suppresses that initial active refresh
and permits the plan only after a real `.background` → `.active` transition.
The gate's three focused tests and the full test-build pass. A before/after
trace must confirm one initial Activity interval and no
`Lifecycle.foreground.refresh` interval before any background transition.
