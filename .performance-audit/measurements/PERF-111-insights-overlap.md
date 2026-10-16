# PERF-111 / #235 — remaining Insights load ownership

## Decision and provenance

On 2026-10-16, the remaining ViewModel defect was reproduced before changing
production code: a completed newer reload was overwritten by an older response.
One bounded correction establishes a shared refresh owner and guards publication.
Stop at this correctness fix; PERF-112's accepted analytics optimization stays closed.

Worktree `.worktrees/performance-baselines`, branch `chore/performance-baselines`,
initial HEAD `bedbeb359dddee230f73ea88443165729c834202`, PR #230 context.
The initial 43 dirty/untracked file fingerprints were saved locally before edits.
No main-checkout change, commit, push, ticket closure or external update was made.
Tests use the isolated `PersonalFinanceTraker-TEST` scheme, Xcode 27.0,
iPhone 17 Simulator / iOS 27.0 (24A434), `pft-performance-baselines`,
UDID `F160101A-8C10-4335-A155-D4156F027578`, en_US / Europe/Rome.
Behavioral tests use Debug-TEST; the financial parity harness uses Release-TEST
with `ENABLE_TESTABILITY=YES`. No physical-device latency claim is made.

## Actual ownership and red-capable loop

`AppShellModels` owns one `CompassViewModel` shared across shells and lock cycles.
Actual callers are Insights' payCycleAware appearance/pay-cycle callback and add-sheet
dismiss, iPhone revision/foreground fan-out, awaited iPad revision/foreground refresh,
Plan's revision-keyed task, iPad Health Score/Goals appearances, and `addFunds`.
The duplicate Insights onAppear remains
removed. The score preference previously launched an independent computation task.

Before this fix, `load()` launched a new unowned `reloadData()` on every request.
`reloadData()` assigned transactions, goals, categories and rules across awaits;
the score path also awaited category reads, snapshot lookup/save and history reads.
MainActor isolation serialized individual synchronous segments, not whole reloads.
The repository's revision-aware cache does not own ViewModel publication.

The minimized diagnostic uses the real ViewModel and existing mock repository's
`fetchAllHandler` continuation. Hold response A (expense EUR 12), replace the
handler with response B (EUR 37), await B's complete `reloadData()`, then deliver A
and await its complete reload. Assert transaction values and explorer totals still
equal B. This is a legal repository-response ordering at the async ViewModel seam;
it does not measure how often a physical actor/UI schedule produces that ordering.

The first valid run executed five tests: four existing tests passed and the diagnostic
failed with `[-12]` rather than `[-37]`. Then the diagnostic ran three times each
with one and 5,000 records: all six parameter executions failed; all twelve existing
test executions passed. The 5k fixture is deliberately simple, homogeneous EUR
expenses, not the richer PERF-112 ledger or an end-to-end navigation benchmark.
The first recorded load sequences are A=1 and B=4 (service intervals share the
sequence counter); commits are B=4 followed by A=1. Later corrected passes carry
explicit requested/published generations in their metadata.

| Before, each of three repetitions | Reads | Starts / commits | Maximum active | Expected / published explorer total |
| --- | ---: | ---: | ---: | ---: |
| 1 record, A then B requests / B then A completion | 2 | 2 / 2 | 2 | 37 / 12 |
| 5,000 records, same ordering | 2 | 2 / 2 | 2 | 185,000 / 60,000 |

Ranked hypotheses after the red: independent publication owners; partial shared
state across awaits; stale repository cache. Explicit A/B responses exclude the
cache as the cause of this reproduction. Both loads read and compute, so obsolete
work and obsolete publication are demonstrated separately. No request was dropped
by a load guard in the old code; the visible late update was lost by overwrite.

Local baseline artifacts: `.build/perf111-red-minimal.xcresult`,
`.build/perf111-red-repeated.xcresult`, diagnostic stdout, and saved red test/source.
Pre-fix ViewModel SHA-256:
`c749de0c313a7d04c9c918d74a51a561ee1866e0dffd18aa3b18b9514a167f96`.
The first method-only filter ran zero tests and is discarded. One suite attempt
stalled in automatic Simulator diagnostic collection and was terminated; its
incomplete bundle is also excluded. Subsequent runs use `-collect-test-diagnostics never`.

## Bounded correction and regression scenarios

`load()` and awaited `reloadData()` now request the same owned task. Requests
advance a generation; a burst during an active pass is coalesced into a fresh
follow-up. A request during that follow-up causes another pass, including after
an error. There is no persistent loaded/cache flag: later navigation and foreground
requests still refresh. Canceling a waiter does not cancel shared work.

Repository inputs and score/history are staged locally. Superseded passes cannot
publish; the current generation publishes all load-owned state without an await.
Explorer uses the selection current at publication. The score preference now uses
the same refresh owner. Financial service formulas, repository protocol, optional-read
fallbacks and daily snapshot policy are unchanged. No view, executor or cache redesign.

The old diagnostic deliberately required B to finish before A was released; that
schedule is prevented by the new owner. Regression tests instead hold A, request
new revisions/navigation, release A, and hold the fresh follow-up before publication.
They assert no A rows were published, then release B and check the final values.

| Corrected burst, 1 and 5,000 records | Requests | Reads | Starts / commits | Maximum active | Published generation |
| --- | ---: | ---: | ---: | ---: | ---: |
| Revision plus repeated appearance/dismiss boundaries | 4 | 2 | 2 / 1 | 1 | 4 |

This is a count/correctness observation, not a timing comparison against the
two-request baseline. Tests additionally cover a revision during the follow-up,
failed first read with a pending update, retry after failed initial and later loads,
canceled waiter, period/type changes, pay-cycle and score-preference changes during
category reads, and supersession at snapshot lookup/history/save boundaries.
Sequential reference loads verify scores/components, recap, averages and
explorer values. A disk-backed integration starts from `SampleData`, uses a second
container to represent external writes, follows the real foreground invalidation
path, then checks an ordinary repository mutation through `CompassViewModel`.

Snapshot side effects have an explicit boundary: a generation is checked after
lookup and immediately before issuing a save. A save already in flight cannot be
recalled when a new request arrives. It remains valid under the existing first-score-
of-the-day history policy; the superseded pass still cannot publish UI state.
The test for that ordering checks one saved daily record and the latest UI rows.
This fix does not promise historical snapshots always track the latest intraday score.

## Validation and reproduction

The initial corrected suite passed 10 tests / 12 parameter executions. The expanded
behavioral run passed 40 tests / 43 executions, zero failures and zero skips, including
real repository/cache/foreground tests. Final validation is recorded below.

The final behavioral run passed **41 tests / 44 executions including parameter cases**, zero
failures and skips; it also covers an awaited Plan/iPad-style reload joining an
appearance-owned pass. Local result: `.build/perf111-green-final.xcresult`.
The isolated optimized analytics harness executed and passed **one test**, zero
skips, with all **70** records and within-run instrumentation-on/off result parity.
Local result: `.build/perf111-release-parity.xcresult`.

Exact comparison with the accepted PERF-112 artifact was correctly rejected:
that run was at local 01:21, this run at 11:43, and `StatisticalAverageService`
uses a production-clock six-month cutoff. Fixture expense indices 2002 and 3827
(EUR 140.88 and 122.63) leave the window in that interval. An independent integer-cent
fixture reconstruction verifies both old and new income/expense/savings averages
at their respective recorded clocks for all 56 records with loaded Insights state.
The other 14 records have zero Insights averages and match exactly. All other result
fields, fetch counts, locale/timezone and service/thread coverage match across all
70 records. This is explained clock drift, not claimed exact historical parity or
a performance improvement. No change was made to the average service or PERF-112.

[Redacted validation counts and comparison outcome](PERF-111-validation.json)
retain this distinction and the corrected ViewModel source hash. Raw stdout,
diagnostics, timing distributions and result bundles stay ignored under `.build`.

Of the original 43 WIP files, 41 remain byte-identical. Only the existing summary
and changelog receive additive/scoped updates for this ticket; their prior content
is preserved. The remaining changes are the Insights ViewModel, its tests, mock
repository test hooks and this ticket's two new reports.
`git diff --check` passed. `graphify update .` completed and left Git status unchanged.

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb test -only-testing:PersonalFinanceTrakerTests/CompassViewModelTests -only-testing:PersonalFinanceTrakerTests/ExplorerPeriodTests -only-testing:PersonalFinanceTrakerTests/ExplorerBreakdownTests -only-testing:PersonalFinanceTrakerTests/FinancialHealthServiceTests -only-testing:PersonalFinanceTrakerTests/TransactionActorCacheTests -collect-test-diagnostics never -testLanguage en -testRegion US
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_ANALYTICS_BASELINE=1 scripts/xcb test -configuration Release-TEST ENABLE_TESTABILITY=YES -only-testing:PersonalFinanceTrakerTests/AnalyticsBaselineTests -collect-test-diagnostics never -testLanguage en -testRegion US
```

Run the analytics harness alone: recorder/settings are process-wide. Inspect
`totalTestCount`, parameter invocation counts, failures and skips in the JSON and
`.xcresult`; exit zero alone is insufficient. Export stdout with `xcresulttool export
diagnostics`. Use the existing PERF-112 summarizer for 70-record financial/count parity,
without interpreting its timing distributions as a new speedup measurement.

Stop after the scoped ownership correction and behavioral/result validation.
Physical gesture-to-frame latency, frequency of the failing order on hardware,
energy, allocations, UI navigation gestures, light/dark, compact/wide layouts,
Dynamic Type and VoiceOver were not measured. ViewModel boundary tests cover
navigation-equivalent requests; they are not UI navigation tests. Independent
goal CRUD tasks and unrelated feature loaders are outside this reproduction.
