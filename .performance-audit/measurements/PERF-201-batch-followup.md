# PERF-201 — Bulk edit and Undo batch follow-up

> Publication note — 2026-10-16: Historical comparable batch experiment. Its source hashes, timing distributions, tests and workflow statements below describe the original run. The implementation is committed in `eba7011`; current publication/integration status is in [the summary](../summary.md). These timings are not rerun claims for the final branch.

## Result and decision

**Mitigated for Activity bulk note/amount/category edits and Undo.** The comparable 5k follow-up performs one save, one full-history materialization and one Safe-to-Spend refresh/write/WidgetKit request per measured edit or Undo, at 1, 10 and 100 selected rows. At 100 rows, local settled median drops from about 11.6 seconds to about 0.21 seconds in Debug Simulator. No physical-device responsiveness claim follows from this result.

Stop structural work for this scope after the passing regression and count budgets. Restore and recurrence remain separately unmeasured PERF-201 paths. Assess actual responsiveness in the isolated PFT TEST app before considering further changes.

## Bounded plan and implementation

1. Add a Sendable row-ID/input batch contract and use it from the existing public bulk edit and Undo caller.
2. Use one operation-owned SwiftData context, resolve selected rows by ID, apply editable fields and save once. On a failed batch save, roll back and retry rows independently, rolling back each failed retry before continuing. Successful rows remain persisted; the existing caller still arms Undo for the captured selection and ignores individual errors.
3. Attempt one final snapshot invalidation/refresh after successful persistence, then retain the existing callback, pending-delete finalization, local reload and Undo flow. Empty or entirely failed batches do not flush. Test partial failures and final values, then repeat the original measurement.

The private context prevents rollback from discarding unrelated pending writes in the actor's long-lived context. The fast path has no suspension until final derived-state refresh. Failure retries may require several saves, but still attempt only one final derived-state refresh. A failing widget/file write retains the existing error handling; one refresh attempt is not a guarantee of successful external I/O.

The single-row update shares field assignment with batch update. No restore, recurrence, search, loader, widget-output equality optimization or UI layout change is included. Bulk input reconstruction now preserves `travelId`; it previously omitted that field, causing note/amount/category edits and their Undo to drop trip membership. Category edits keep their existing sign conversion and goal-clearing behavior; Undo restores prior values.

## Measurement provenance and comparability

Use the original [baseline](PERF-201-baseline.md) for the pre-fix artifact and exact protocol. Both measurements use branch `chore/performance-baselines`, HEAD `d1b7f5b` plus dirty WIP, the isolated TEST bundle, Debug-TEST/arm64, iPhone 17 Simulator iOS 27.0 (24A434), macOS 27.0, `en_US`/Europe-Rome, fixed 5,000-row disk fixture, pay-cycle day 1/buffer 5%, enabled instrumentation, three rotated rounds and the same public ViewModel seam. Source hashes and exact test timestamps are in the [JSON companion](PERF-201-batch-followup.json). The final-source confirmation is the primary follow-up below; an earlier successful follow-up is retained as supplemental evidence.

The harness modification adds explicit count assertions after the timed interval; it does not change fixture generation, timed boundaries or record fields. The ViewModel remains unmounted, its AppShell callback is replaced with a counter, and local reload/grouping are awaited. Global shell fan-out, input gestures, main-thread CPU and actual displayed frames are excluded. Host load/thermal state were not controlled; these are small simulator distributions, not field telemetry or Release device latency.

Local ViewModel settled duration in milliseconds: pre-fix median → final-source follow-up median [follow-up min–max], three repetitions per cell:

| Selected rows | Edit | Undo |
| ---: | ---: | ---: |
| 1 | 174.33 → **172.47** [172.11–205.48] | 170.43 → **179.13** [167.08–181.23] |
| 10 | 1,217.41 → **177.35** [176.53–190.56] | 1,224.77 → **180.81** [175.03–191.53] |
| 100 | 11,558.54 → **215.34** [214.31–231.02] | 11,602.63 → **204.17** [202.95–215.48] |

No single-row speedup is established. The effect is removal of selected-row amplification: 100-row full materializations go from 100 × 5,000 to 1 × 5,000 snapshots per phase. There are still up to N targeted row-ID lookups in the write context; the full-store fetch counter does not count those lookups. Their time is included in the operation interval.

| Counter per phase | Before, 100 rows | After, every tested row count |
| --- | ---: | ---: |
| Successful saves | 100 | 1 |
| Full-store fetches / materializations | 100 / 100 | 1 / 1 |
| Safe-to-Spend refreshes / snapshot writes | 100 / 100 | 1 / 1 |
| WidgetKit reload requests | 100 | 1 |

WidgetKit requests do not count actual OS timeline executions. Nested refresh/fetch/map/write wall intervals must not be added; `snapshot.write` includes computation and the widget request rather than file I/O alone.

## Validation

- Final targeted regression: **93 test methods passed, zero failures, two intentional opt-in skips**; parameterized arguments bring the device-level passed execution count to 96. Coverage: `BulkEditBatchTests`, `BulkEditBaselineTests`, `TransactionListViewModelTests`, `TransactionActorCacheTests`, `SearchTests`, `SafeToSpendSnapshotBuilderTests`, `SafeToSpendSnapshotTests`.
- Dedicated behavioral/widget run: **7 methods passed, zero failures/skips**, including all three note/amount/category arguments. Checks selection scope, metadata, goal/sign/category semantics, lossless Undo, a pending-delete-to-edit transition, warmed-reader freshness, empty/deleted targets, partial-save fallback and all-failed rollback with a later successful operation.
- Monetary-widget test checks final persisted widget values against the builder using the snapshot's own timestamp, confirms the amount actually changes and verifies Undo restores the previous financial values. It is TEST-only and restores prior TEST widget data/preferences. Failure injection drives real context mutation/rollback/save, but is not a full-disk/corrupt-store experiment.
- Final 5k follow-up: **2 methods passed, zero failures/skips**, all 18 samples pass data/grouping/widget checks and the new one-save/one-materialization/one-widget-request budgets.
- The original structural red oracle now passes both arguments: one selected row → one materialization; two selected rows → one materialization. The pre-fix two-row result was two materializations and failed that same budget.
- `git diff --check` passes. Graphify updated with unchanged Git status. Existing dirty work is preserved; only explicitly scoped production/test/changelog/audit files are edited.

No user-facing view hierarchy or styling changed. Light/dark, compact/wide layout, Dynamic Type and VoiceOver visual checks were not run. Physical-device timing, concurrent-writer races, broad failure conditions and iPad performance remain unverified.

## Reproduce

Count/timing follow-up, run alone:

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_BULK_BASELINE=1 TEST_RUNNER_PFT_BULK_REQUIRE_BATCH=1 TEST_RUNNER_PFT_BULK_SINGLE_FLUSH_CHECK=1 scripts/xcb test -only-testing:PersonalFinanceTrakerTests/BulkEditBaselineTests -testLanguage en -testRegion US
```

Behavioral checks with real final widget file, run alone in TEST:

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_BULK_WIDGET_CHECK=1 scripts/xcb test -only-testing:PersonalFinanceTrakerTests/BulkEditBatchTests -testLanguage en -testRegion US
```

Final targeted regression (expensive baseline and widget-file check skipped here because each ran separately):

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_BULK_SINGLE_FLUSH_CHECK=1 scripts/xcb test -only-testing:PersonalFinanceTrakerTests/BulkEditBatchTests -only-testing:PersonalFinanceTrakerTests/BulkEditBaselineTests -only-testing:PersonalFinanceTrakerTests/TransactionListViewModelTests -only-testing:PersonalFinanceTrakerTests/TransactionActorCacheTests -only-testing:PersonalFinanceTrakerTests/SearchTests -only-testing:PersonalFinanceTrakerTests/SafeToSpendSnapshotBuilderTests -only-testing:PersonalFinanceTrakerTests/SafeToSpendSnapshotTests -testLanguage en -testRegion US
```

Raw diagnostics remain ignored under `.build/perf201/`; sanitized samples, summaries, source hashes and validation results are in the JSON companion. No commit, push or PR update is included.
