# PERF-110 baseline — global refresh fan-out

> Publication note — 2026-10-16: Historical pre-mitigation refresh baseline. The measured multiplicity below is not asserted as current behavior. Scoped snapshot/lifecycle fixes and the latest integration checkpoint are indexed in [the summary](../summary.md).

Status: `IN_PROGRESS` — scenarios 110-B through 110-D complete; 110-A remains provisional

Confidence before measurement: `Strong Evidence`

## Question

How many full repository reads, feature reloads, snapshot refreshes, and WidgetKit reload requests are caused by one logical lifecycle or data-change event with a 5k ledger?

## Scenarios

| ID | Scenario | Scenario label | Status |
| --- | --- | --- | --- |
| 110-A | Cold launch with an existing PIN | `cold-launch-5k` | Provisional run 1 captured |
| 110-B | Add one transaction | `add-transaction-5k-r1` … `r5` | Complete: 5 equivalent runs |
| 110-C | Background then foreground with no external data change | `noop-foreground-5k-r1` … `r5` | Complete: 5 equivalent runs |
| 110-D | Foreground after an App Intent transaction | `intent-foreground-5k-r1` … `r5` | Complete: 5 equivalent runs |

## Metrics to capture

- `DataChangedSignal.bump`
- `Shell.refreshFanOut`
- `TransactionActor.fetchAll.start/completed`
- Dashboard/Activity/Insights loader request, start, commit, end
- `Habit.refresh` and `Habit.snapshot.write`
- `SafeToSpend.refresh` and `SafeToSpend.snapshot.write`
- `WidgetKit.reload.request` split by kind
- `Lifecycle.bootstrap` or `Lifecycle.foreground.refresh`

## Run protocol

1. Seed once using the instructions in `environment.md`, then relaunch without the seed argument.
2. Ensure the PIN already exists and dismiss onboarding/tips before the measured interaction.
3. Start a fresh unified-log capture and label the launch with the scenario name.
4. Perform exactly one scenario action; do not navigate elsewhere unless the scenario requires it.
5. Background the app to force a counter summary, stop the capture, and preserve the raw log under `traces/` locally.
6. Repeat at least five times after one unmeasured warm-up. Record individual runs and the median only after verifying equivalent event sequences.

## Provisional results

Run 1 was a fresh app process after the seed run, on the Debug iOS 27.0 simulator. The existing fixture PIN was present, but the lock screen was not dismissed; the current architecture mounts and refreshes the shell behind that overlay. Work had settled by the final recorded event.

| Metric | Run 1 count |
| --- | ---: |
| `TransactionActor.fetchAll` completed | 23 |
| Dashboard loads started / committed | 4 / 4 |
| Activity loads started / committed | 4 / 4 |
| Insights loads started / committed | 3 / 3 |
| `DataChangedSignal.bump` | 2 |
| `Shell.refreshFanOut` | 2 |
| Habit refreshes | 4 |
| Safe-to-Spend refreshes | 4 |
| Habit WidgetKit reload requests | 8 |
| Safe-to-Spend WidgetKit reload requests | 4 |

This directly reproduces the fan-out shape, but it is only one Debug/simulator run. PERF-110 remains `Strong Evidence` until repeated runs establish a stable structural baseline; no user-facing timing, energy, or battery claim is made from these numbers.

## No-op foreground results

Five runs used a real Home/background transition through Device Hub, followed by reopening the still-running app process. `simctl launch` was used only to foreground that existing process; it returned the same PID that was started for the run. Each run then returned to Home once more to close the measured segment and emit the counter summary.

Startup work and late work that completed while the app was first in the background were excluded. The measured segment begins at the post-background `Lifecycle.scenePhase phase=active` event and ends at the next `phase=inactive` event. No transaction, goal, setting, or other persisted data was changed between those boundaries.

| Metric in foreground segment | r1 | r2 | r3 | r4 | r5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `Lifecycle.foreground.refresh` started / completed | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| `TransactionActor.fetchAll` completed | 12 | 12 | 12 | 12 | 12 |
| Dashboard loads started / committed | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Activity loads started / committed | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Insights loads started / committed | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| `DataChangedSignal.bump` | 1 | 1 | 1 | 1 | 1 |
| `Shell.refreshFanOut` | 1 | 1 | 1 | 1 | 1 |
| Habit refreshes / snapshot writes | 2 / 4 | 2 / 4 | 2 / 4 | 2 / 4 | 2 / 4 |
| Safe-to-Spend refreshes / snapshot writes | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Habit / Safe-to-Spend WidgetKit requests | 4 / 2 | 4 / 2 | 4 / 2 | 4 / 2 | 4 / 2 |
| Maximum concurrent `fetchAll` | 2 | 2 | 2 | 2 | 2 |
| Cancelled / failed intervals | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

The repeated sequence confirms the structural PERF-110 mechanism for a no-op iPhone foreground: the lifecycle handler starts one complete feature/snapshot refresh plan, then its unconditional `DataChangedSignal.bump` triggers a second complete plan. PERF-110 is therefore `Confirmed` for multiplicity and reachable overlap in this scenario. Debug/simulator duration is not treated as evidence of user-visible delay, memory pressure, or energy impact.

## Manual transaction results

After one unmeasured warm-up, five runs each started from a freshly reset 5,000-transaction dataset. The audit-only skip-lock flag exposed the production form without changing its save path. In each run the same UI interaction added a €12.00 Groceries expense, and the dismissed sheet plus the dashboard's `Groceries, -12,00 €` row visually confirmed the mutation.

The measured save segment begins with the `SafeToSpend.refresh` whose repository fetch first returns 5,001 items. This captures the refresh initiated by `TransactionActor.add` immediately before the form calls `DataChangedSignal.bump`, followed by the shell fan-out caused by that bump. It ends at the next `Lifecycle.scenePhase phase=inactive` or `phase=background` event. Form presentation, typing time, startup work that still read 5,000 items, and work emitted after the closing boundary are excluded.

| Metric in manual-save segment | r1 | r2 | r3 | r4 | r5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `TransactionActor.fetchAll` completed | 7 | 7 | 7 | 7 | 7 |
| Dashboard loads started / committed | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| Activity loads started / committed | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| Insights loads started / committed | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| `DataChangedSignal.bump` | 1 | 1 | 1 | 1 | 1 |
| `Shell.refreshFanOut` | 1 | 1 | 1 | 1 | 1 |
| Habit refreshes / snapshot writes | 1 / 2 | 1 / 2 | 1 / 2 | 1 / 2 | 1 / 2 |
| Safe-to-Spend refreshes / snapshot writes | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Habit / Safe-to-Spend WidgetKit requests | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Maximum concurrent `fetchAll` | 1 | 1 | 1 | 1 | 1 |
| Cancelled / failed intervals | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

This confirms that a single in-app transaction save reaches the PERF-110 mechanism: the write performs one immediate Safe-to-Spend repository read and widget refresh, then the global data-change fan-out performs six more repository reads plus all three feature loads and both widget pipelines. The result is structural evidence only; the Debug simulator does not establish physical-device latency, memory, responsiveness, battery, or energy impact.

## App Intent transaction plus foreground results

Five runs started from a freshly reset 5,000-transaction dataset and the same running app process. The local `PFT Audit Add Transaction` shortcut invoked the app's `Add Transaction` intent for an Expense in Groceries. The executed system result was €12.00 in every run; although the shortcut editor had displayed `12,34`, that value was not observed at execution. Each mutation was verified by repository fetches returning 5,001 items before the app was foregrounded, and `simctl launch` returned the original PID for every foreground transition.

The mutation-specific segment begins with the `SafeToSpend.refresh` whose repository fetch first returns 5,001 items and ends before the subsequent inactive-to-active foreground transition. This excludes settled or late startup work that still read 5,000 items. The foreground segment begins at that post-intent `Lifecycle.scenePhase phase=active` event and ends at the next `phase=inactive` or `phase=background` event. Work emitted after the closing boundary is excluded.

### App Intent mutation segment

| Metric before foreground | r1 | r2 | r3 | r4 | r5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `TransactionActor.fetchAll` completed | 2 | 2 | 2 | 2 | 2 |
| Habit refreshes / snapshot writes | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| Safe-to-Spend refreshes / snapshot writes | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| Habit / Safe-to-Spend WidgetKit requests | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| `DataChangedSignal.bump` / `Shell.refreshFanOut` | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Cancelled / failed intervals | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

### Post-intent foreground segment

| Metric in foreground segment | r1 | r2 | r3 | r4 | r5 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `Lifecycle.foreground.refresh` started / completed | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| `TransactionActor.fetchAll` completed | 12 | 12 | 12 | 12 | 12 |
| Dashboard loads started / committed | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Activity loads started / committed | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Insights loads started / committed | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| `DataChangedSignal.bump` | 1 | 1 | 1 | 1 | 1 |
| `Shell.refreshFanOut` | 1 | 1 | 1 | 1 | 1 |
| Habit refreshes / snapshot writes | 2 / 4 | 2 / 4 | 2 / 4 | 2 / 4 | 2 / 4 |
| Safe-to-Spend refreshes / snapshot writes | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| Habit / Safe-to-Spend WidgetKit requests | 4 / 2 | 4 / 2 | 4 / 2 | 4 / 2 | 4 / 2 |
| Maximum concurrent `fetchAll` | 2 | 2 | 2 | 2 | 2 |
| Cancelled / failed intervals | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

Across one logical App Intent transaction followed by one foreground, the two bounded segments therefore perform 14 repository reads, three Habit refreshes with five Habit snapshot writes, three Safe-to-Spend refreshes with three Safe-to-Spend writes, and eight WidgetKit reload requests. The foreground fan-out is structurally identical to the no-op foreground baseline: the external data change does not suppress or consolidate the duplicated lifecycle plan.

This confirms PERF-110 for a second reachable path, including a real out-of-process App Intent mutation. These Debug/simulator counts prove repeatable work multiplicity only; they do not establish physical-device latency, memory, responsiveness, battery, or energy impact.

## Physical-device exploratory trace

`traces/PERF-110-device-manual-save-r2.env.trace` is a retained 28.344-second
Time Profiler recording on the iPhone 14 Pro Max running iOS 27.0.1. Its
launched process received `-performanceAudit` with scenario
`device-manual-save-5k-gui-r2`, and the user performed the manual-save flow.
It is an authentic Release/Profile device trace, not a simulator result.

The trace alone is not an accepted manual-save timing run: only one run exists,
the device dataset count and thermal state were not independently recorded in
the trace, and the current command-line export did not yield a bounded
PFT-signpost interval with which to isolate the save. It remains available for
interactive inspection in Instruments and is excluded from medians, latency,
memory, responsiveness, and energy conclusions until a repeatable extraction
protocol is established.

### Physical-device manual-save observation

The Logging-template trace
`traces/PERF-110-device-manual-save-r3.env.trace` retained the same launch
arguments and displayed the following `PFT_PERF` messages in Instruments. The
scenario label is `device-manual-save-5k-gui-r2`; the physical trace file is
named `r3` because it followed an exploratory Time Profiler capture.

The save is bounded by the immediate Safe-to-Spend read changing from the
pre-save 5,006-item fixture to `items=5007`. The event starts at 00:17.518;
the global revision bump occurs at 00:17.625 and iPhone shell fan-out begins
at 00:17.627.

| Observed post-save work | Physical-device result |
| --- | --- |
| `TransactionActor.fetchAll` completions | 7 (sequences 44, 46, 49, 52, 53, 54, 57) |
| Aggregate recorded `fetchAll` interval duration | 719.8 ms |
| First post-save fetch duration | 105.3 ms |
| Six fan-out/later fetch durations | 88.0, 87.8, 87.2, 114.5, 138.7, 98.3 ms |
| `DataChangedSignal.bump` then `Shell.refreshFanOut` | 2.4 ms apart |
| `Activity.load` | 177.4 ms |
| `Dashboard.load` | 1.653 s |
| `Insights.load` | 1.614 s |
| `Habit.refresh` | 1.493 s |
| Final `SafeToSpend.refresh` | 120.5 ms |

The Points of Interest rows also identify the execution context. The immediate
post-save Safe-to-Spend interval (sequence 43, 106.6 ms) begins and ends on
the Main Thread. `Insights.load` sequence 50 likewise begins and ends on the
Main Thread over 1.61 seconds. The first three post-save `fetchAll` intervals
(sequences 44, 46, and 49) are recorded on the Main Thread; the remaining
four are recorded on app worker threads. These are interval ownership markers,
not CPU samples: they do not establish that an interval consumed its entire
wall duration on the main thread, and therefore do not by themselves upgrade
PERF-112's confidence.

This physical observation reproduces the same seven-fetch manual-save shape
as the five Debug/simulator runs and also records overlapping feature work.
It confirms PERF-110's multiplicity on a physical Release/Profile run. It is
not an end-to-end user-latency claim: it is a single launch-contaminated run
on a fixture that had reached 5,007 transactions after earlier attempts, with
no thermal-state or repeated-run distribution.

## Acceptance/rejection rule

## Home-to-Activity follow-up measurements (after coalescing fix)

One Debug/simulator run (`home-to-activity-r2`, 40 transactions) kept the app
on Home, then switched to Activity after the initial work had settled. The
user reported the switch at `00:13.055`. At that point two
`Activity.load.request` events were still emitted, but both were recorded as
`Activity.load.skipped`; there was no subsequent `Activity.load` interval and
no subsequent `TransactionActor.fetchAll` interval.

The last actual Activity load had already completed at `00:10.928`, before the
tab switch. The trace therefore replaces the previous tab-switch observation
of 13 full repository reads in about one second with zero repository reads
caused by the measured switch. Two overlapping repository reads at
`00:10.486` preceded the switch and are excluded from this result.

This is a single, small-dataset Debug/simulator structural measurement. It
confirms that the new coalescing/settled-state guard prevents the expensive
Activity reload on this path; it does not establish physical-device latency,
energy, or a distribution across datasets and runs.

The same sequence was then repeated on the seeded 5,000-transaction dataset
(`home-to-activity-5k-r1`). The last prewarm Activity interval completed at
`00:12.649`; the user switched tabs at `00:33.077`. As in the 40-item run,
the switch emitted two `Activity.load.request` events and two corresponding
`Activity.load.skipped` events, with zero subsequent `Activity.load` intervals
and zero subsequent `TransactionActor.fetchAll` intervals. The earlier 11
repository reads and two Activity loads occurred before the measured tab
switch and are not attributed to it.

This repeat confirms the fix's structural result at the audit's realistic
ledger size. It remains a single Debug/simulator run for that size and does
not establish physical-device latency, energy, or a distribution across runs.

- Confirm the multiplicity claim only if one logical event consistently produces multiple full feature refreshes or repeated `fetchAll`/snapshot work.
- Downgrade or reject the finding if the counters show one settled refresh plan and no meaningful duplicate work.
- Do not infer UI responsiveness or battery impact from structural counts alone.
