# PERF-111 baseline — duplicate and overlapping loaders

> Publication note — 2026-10-16: Historical duplicate-loader baseline. The later shared-owner/supersession correction and its regression evidence are in [PERF-111-insights-overlap.md](PERF-111-insights-overlap.md). Current publication status is in [the summary](../summary.md).

Status: `CONFIRMED` for duplicate appearance ownership and reachable overlap; other PERF-111 scenarios remain pending

Confidence before measurement: `Strong Evidence`

Confidence after measurement: `Confirmed`

## Question

Do normal navigation and refresh events start duplicate or overlapping Dashboard, Activity, or Insights loads, and which generations actually commit?

## Scenarios

| ID | Scenario | Scenario label | Status |
| --- | --- | --- | --- |
| 111-A | Open Insights once through the existing destination route | `open-insights-5k-r2`, `open-insights-5k-r3` | Reproduced twice |
| 111-B | Add one transaction and dismiss the sheet | `save-dismiss-5k` | Pending |
| 111-C | Background/foreground rapidly | `rapid-resume-5k` | Pending |
| 111-D | Trigger a data revision while a 5k load is active | `revision-during-load-5k` | Pending; deterministic harness not yet added |

## Metrics to capture

- `Dashboard.load`, `Activity.load`, `Insights.load` start/commit/outcome counts
- maximum concurrent intervals for each loader
- load and reload request counts
- `Dashboard.load.skipped` and `Activity.load.skipped`
- `TransactionActor.fetchAll` calls nested in the scenario window
- loader sequence IDs and commit order
- cancellations and failed outcomes

## Run protocol

Use the common seed/log protocol in `PERF-110-baseline.md`. For `111-A`, use the existing `pending_widget_destination=insights` launch route after seeding and do not change the pay-cycle setting or present another sheet. For scenarios involving overlap, preserve timestamps and sequence IDs rather than relying only on totals.

## Results

The provisional `cold-launch-5k` run recorded overlapping Dashboard loads (maximum concurrency 2) and overlapping Insights loads (maximum concurrency 2). All four Dashboard generations and all three Insights generations committed; no cancellation was recorded. Activity reached four loads but did not overlap in this run.

The first attempt at `open-insights-5k` did not reach the tab bar because the PIN UI lives in a separate modal overlay window that XCUITest did not unlock. Its three Insights loads were lifecycle traffic, not evidence of a navigation trigger, so they are excluded from scenario `111-A`. The retry uses the app's existing widget-destination route, a Debug-only lock bypass, and explicit call-site trigger labels.

Runs `r2` and `r3` produced the same attributed sequence:

- one `Insights.load.trigger source=payCycleAware`;
- one `Insights.load.trigger source=onAppear` at the same timestamp;
- two distinct `Insights.load.request` events from those triggers;
- maximum Insights loader concurrency of 5 after lifecycle fan-out;
- 5 commits and 5 completed intervals;
- 0 cancellations and 0 failed intervals.

The duplicated appearance ownership and reachable overlap are therefore `Confirmed`. The measured durations are Debug/simulator observations and are not used to claim user-facing latency, energy impact, or a physical-device performance budget. Scenarios 111-B through 111-D remain open for the broader finding.

## Acceptance/rejection rule

- Confirm duplicate load ownership when one navigation event produces more than one equivalent Insights start.
- Confirm overlap only when interval timestamps overlap or the recorded maximum concurrency is greater than one.
- A duplicate request that is consistently skipped by an existing guard is not equivalent to duplicate expensive work; report both counts.
- A committed older sequence is a stale-publication risk only if a newer sequence already existed; do not claim incorrect UI without reproducing it.
