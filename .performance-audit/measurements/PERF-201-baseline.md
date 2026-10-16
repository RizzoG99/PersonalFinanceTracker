# PERF-201 — Bulk edit and Undo baseline

> Publication note — 2026-10-16: Historical pre-batch baseline, retained for comparison with [the batch follow-up](PERF-201-batch-followup.md). Its JSON correctly records that no optimization was present in that measured source; it does not describe the final implementation.

Follow-up: [batch implementation and comparable measurements](PERF-201-batch-followup.md). This baseline retains the pre-fix evidence below.

## Decision

**Per-row amplification is confirmed for Activity bulk note edit and Undo.** With 100 selected rows in a 5,000-transaction ledger, each phase performs 100 saves, 100 full-store fetches/materializations, 100 Safe-to-Spend refreshes/writes and 100 WidgetKit reload requests. This establishes a measured reason to investigate one batch boundary. No production optimization is included in this checkpoint.

Restore, recurrence, partial failures and physical-device responsiveness remain unmeasured. The existing source-level finding is broader than this experiment.

## Provenance and scope

- Worktree `.worktrees/performance-baselines`, branch `chore/performance-baselines`, HEAD `d1b7f5b48a0bf2ee882639cfbc3171fe7d826eb0`, plus preserved dirty WIP (PR #230 context).
- Scheme `PersonalFinanceTraker-TEST`, Debug-TEST, arm64, bundle `rizzoG99.PersonalFinanceTraker.test`; personal installation/store excluded.
- iPhone 17 simulator `pft-performance-baselines`, iOS 27.0 (24A434), macOS 27.0 host. Simulator UDID `F160101A-8C10-4335-A155-D4156F027578`.
- Baseline: 2026-10-15 23:57:57–23:59:58 Europe/Rome; `en_US`, pay-cycle day 1, buffer 5%. Instrumentation enabled equally throughout.
- New opt-in harness: [BulkEditBaselineTests.swift](../../PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/TransactionListView/BulkEditBaselineTests.swift). Real ViewModel, repository, disk-backed temporary SwiftData store, Safe-to-Spend writer and TEST WidgetKit request path. No mock persistence and no personal transactions.
- Three rounds with row-count orders `[1,10,100]`, `[100,1,10]`, `[10,100,1]`; edit then Undo at each size, 18 samples. Each round creates a fresh deterministic 5,000-row fixture spanning five years, anchored at epoch `1791547200`. Each Undo restores original state before the next selection.
- TEST preferences and previous widget snapshot file are restored after the harness. WidgetKit requests themselves cannot be recalled.

The ViewModel is not attached to SwiftUI. Its AppShell callback is replaced with a counter. Timing starts at the public bulk edit/Undo call, measures the mutation-task return, and then awaits local reload/grouping completion. It excludes selection gestures, actual frame presentation and global AppShell refresh fan-out. This is a warmed local-ViewModel measurement, not end-to-end UI latency.

## Results

Local ViewModel settled duration, milliseconds; median and range of three repetitions per cell:

| Selected rows | Edit median [min–max] | Undo median [min–max] |
| ---: | ---: | ---: |
| 1 | 174.33 [172.89–191.16] | 170.43 [166.40–181.15] |
| 10 | 1,217.41 [1,209.90–1,231.36] | 1,224.77 [1,200.93–1,233.76] |
| 100 | 11,558.54 [11,410.80–11,675.49] | 11,602.63 [11,429.96–11,655.43] |

For **every** edit and Undo sample, each counter below equals the selected row count N:

| Work per logical operation | 1 row | 10 rows | 100 rows |
| --- | ---: | ---: | ---: |
| SwiftData saves | 1 | 10 | 100 |
| Full-store fetches | 1 | 10 | 100 |
| Full 5,000-row snapshot materializations | 1 | 10 | 100 |
| Safe-to-Spend refreshes | 1 | 10 | 100 |
| Safe-to-Spend snapshot writes | 1 | 10 | 100 |
| WidgetKit reload requests | 1 | 10 | 100 |

At 100 rows this constructs 500,000 transaction snapshots per phase, or one million for edit plus Undo. A WidgetKit request count does not establish how many timelines the OS actually reloads.

Median aggregate wall intervals for the 100-row edit:

| Boundary | Milliseconds |
| --- | ---: |
| Mutation task return | 11,478.93 |
| `SafeToSpend.refresh` | 11,234.16 |
| `TransactionActor.store.fetch` | 5,561.96 |
| `TransactionActor.snapshots.map` | 4,715.11 |
| `SafeToSpend.snapshot.write` | 391.48 |

These intervals are nested; do not add them. The refresh interval accounts for approximately 98% of mutation-task wall time. The snapshot-write marker includes computation, file write and WidgetKit request, so it is not a file-I/O-only measurement. These are wall intervals, not sampled CPU or main-thread execution time.

## Mechanism and correctness

The real public call reaches `TransactionListViewModel.applyBulkEdit`: it awaits `repo.update` once per selected row; Undo repeats the same per-row update pattern. `TransactionActor.update` saves, invalidates the snapshot cache and awaits `refreshSafeToSpendWidgetSnapshot`. The refresh immediately calls `fetchAll`, which fetches/maps the complete history after each invalidation. The measured counts and nested intervals match this mechanism.

The baseline passed with all 18 samples. Assertions check selected notes, unchanged unselected snapshots, complete Undo restoration, all 5,000 IDs/rows retained, current ViewModel/grouped state, one data-change callback per phase and unchanged financial widget values for note-only edits. No measured interval remained active or recorded failure. Fixture-owned save notifications and actor-owned materialization generation are checked against process-wide fetch/map counters to reject contamination.

This verifies the note-edit path. It does not prove category/amount/date edit semantics, concurrent writers, pending-Undo replacement or mid-batch failure behavior. No user-facing views changed; appearance, Dynamic Type and VoiceOver checks were not run for this diagnostic-only addition.

## Reproduction

Run the baseline alone on the isolated TEST simulator:

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_BULK_BASELINE=1 scripts/xcb test -only-testing:PersonalFinanceTrakerTests/BulkEditBaselineTests -testLanguage en -testRegion US
```

The expensive test is disabled unless its explicit flag and TEST bundle ID both match. Judge the JSON summary and captured `PFT_BULK_BASELINE` records; an exit code alone is insufficient. The captured baseline executed one test, passed, with zero failures/skips. A later method-only filter selected zero tests and was discarded as invalid evidence.

The separate opt-in `PFT_BULK_SINGLE_FLUSH_CHECK` exercises the same public path with one and two rows and a structural budget of one full-history materialization per logical edit. This budget detects amplification; it is not a user-visible latency threshold.

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST TEST_RUNNER_PFT_BULK_SINGLE_FLUSH_CHECK=1 scripts/xcb test -only-testing:PersonalFinanceTrakerTests/BulkEditBaselineTests -testLanguage en -testRegion US
```

The executed parameter results are **1 row: Passed, 1 materialization; 2 rows: Failed, 2 materializations against budget 1**. The only recorded assertion failure is this intended structural signal; note-change assertions passed. The expensive baseline is skipped in this separate invocation. This is an opt-in red diagnostic, not a newly introduced production regression or a passing regression suite. Both arguments completed in under 0.4 seconds individually. Xcode then stalled collecting simulator diagnostics; its collection child and parent were interrupted to finalize the result bundle. The exported test tree and stdout verify execution independently of the resulting process exit code 75. No simulator reset was needed.

Sanitized samples, aggregates and result provenance: [PERF-201-baseline.json](PERF-201-baseline.json). Raw runner diagnostics remain ignored under `.build/perf201/`.

## Next bounded experiment

Design one explicit bulk-update boundary for edit and Undo, with one guaranteed final snapshot flush. First establish partial-failure, pending-Undo and final-state semantics: the current caller ignores individual update errors, so changing to all-or-nothing persistence would change behavior. Preserve selection scope, metadata and widget freshness. Re-run this identical 1/10/100-row harness and the structural oracle after any change; compare counts and wall intervals without predicting a speedup. Use a comparable optimized physical-device recording to assess actual responsiveness. Restore and recurrence remain separate later scenarios.
