# Activity search with 5,000 transactions — 2026-10-15

> Publication note — 2026-10-16: Historical 5k ViewModel timing baseline. Its samples, source hashes and configuration remain those recorded below; publishing this report does not turn them into current-device or final-branch timings. A fresh harness verification is recorded at the publication checkpoint in [the summary](../summary.md).

Status: ViewModel baseline measured; keyboard/typing/presentation responsiveness remains unverified. No optimization or production/UI change was made. No PR update or commit was made.

## Provenance and scope

- Worktree: `.worktrees/performance-baselines`; branch `chore/performance-baselines`; HEAD `d1b7f5b48a0bf2ee882639cfbc3171fe7d826eb0`; PR context #230.
- Pre-existing WIP: five audit documents, Xcode project/shared scheme, existing untracked measurement notes and Xcode Cloud staging files. SHA-256 hashes of all 16 pre-existing nonignored dirty files were captured before editing and checked afterward. Their contents were preserved.
- One baseline experiment; no causal intervention or before/after comparison. No accepted product latency budget was found. The proposed 500 ms query-to-result budget has **not** been agreed with the user and is not used as a pass/fail claim.
- Diagnostic test build: Debug, arm64, macOS 27.0 host; worktree simulator `pft-performance-baselines`, iPhone 17, iOS 27.0 (24A434), UDID `F160101A-8C10-4335-A155-D4156F027578`. Test action ran 2026-10-15 11:51:10–11:51:44 Europe/Rome; test method duration 8.507 s. Instrumentation enabled; no Instruments CPU capture in this experiment.
- Fixed synthetic fixture: 5,000 immutable transaction snapshots, anchor epoch 1791547200, 365 dates, two categories, alternating Coffee/Groceries notes, negative integer Decimal amounts, no travels. Repository fixture loaded and grouping awaited before measurement. Fixture construction, SwiftData fetch/mapping and initial load are excluded. Language/time zone and thermal state were not pinned/recorded; the ASCII query oracles are fixture-defined.
- The real `TransactionListViewModel` performs filtering, derived-state updates, grouping, publication and pagination. A mock supplies only repository data; this is not a rewritten filtering benchmark. No existing app ledger is seeded or modified. The measured ViewModel is not attached to a SwiftUI view.

## Boundaries before attribution

| Stage | Current seam / evidence | Limits |
| --- | --- | --- |
| Keyboard opening / typing | SwiftUI `.searchable`, `ActivityView.swift:61` | No keyboard or hardware-input timestamps; not driven by this test. Keyboard-only capture must precede typing. |
| Query request | Test clock immediately before assigning `searchText` | No corresponding production query/generation marker. Not a physical keystroke. |
| Debounce | `searchText.didSet`, 250 ms sleep; `TransactionListViewModel.swift:130` | Intended delay; actual wake/executor wait not separately marked. Cancellation before expiry is outside this serial experiment. |
| Filter | `Activity.filter`, detached worker over all 5,000 snapshots | Wall interval, not sampled CPU. Clear takes the unfiltered fast path and starts no filter worker. |
| Filtered-state publication | `filteredItems` assignment and synchronous `Activity.derivedFilters` | Derived interval covers categories/icons/totals, not the whole assignment. No generation or full filtered-publication marker. |
| Group / publication | `Activity.group`, then `Activity.group.publish` | Named intervals distinguish background grouping and MainActor assignment; their return does not imply frame presentation. |
| Page / presentation | Explicit `activityPage` read after grouping; existing body/list appearance markers | Page construction is measured; actual SwiftUI layout/render and first visible result are not. `onAppear` is not a presented-frame marker. |

Recorder begin/end logs confirm `main=false` for synchronous filter/group intervals, and `main=true` for derived filters/group publication. The test checks per-sample interval cardinality (one of each, except zero filter intervals on clear) and no unfinished measured intervals, rejecting contamination from another Activity instance. Snapshot deltas measure interval wall time. End-to-end test clocks additionally include scheduling, recorder overhead and the 250 ms debounce. These intervals are not Time Profiler CPU weights and must not be added to infer a freeze.

## Results

One first-use sequence plus five warm sequences; 24 samples total. Warm values below are medians in milliseconds; brackets give the observed min–max for query-to-group return. `query-to-group` stops after grouped state has been assigned, before layout/presentation. It includes debounce and scheduling.

| Action | Results | Filter | Derived filters | Group | Group publish | Query-to-group |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Coffee` | 2,500 | 23.104 | 3.325 | 11.140 | 0.599 | 316.627 [315.099–330.181] |
| Extend to `Coffee 4242` | 1 | 39.360 | 0.041 | 0.063 | 0.396 | 320.306 [319.346–328.550] |
| `zzqnomatch` | 0 | 38.652 | 0.023 | 0.011 | 0.007 | 315.908 [306.872–318.172] |
| Clear | 5,000 | — | 7.006 | 20.744 | 0.004 | 305.289 [301.941–313.627] |

Page preparation warm medians: 0.083 / 0.009 / 0.005 / 0.084 ms respectively. First-sequence query-to-group durations: 320.461 / 321.775 / 331.987 / 310.578 ms. This is first search after a warmed fixture load, not cold process launch.

The JSON companion retains every sample and per-action first/warm summaries. All query-to-group samples were below 332 ms in this experiment. This does **not** establish a device responsiveness pass or a general 5,000-transaction limit: data complexity, build, hardware, rapid overlapping queries and SwiftUI observers differ from everyday use.

Test summary: **1 passed, 0 failed, 0 skipped, totalTestCount 1**. Every sample checked expected result counts, equality of grouped and filtered IDs, pagination at 200 rows and the remaining count. This is a behavioral and stage-timing oracle; it cannot go red on a keyboard/layout stall. No exact perceived slowdown was supplied or reproduced, so the diagnosing-bugs gate for a user-symptom loop is still open. No root-cause hypotheses or speculative fixes follow from this baseline.

## Existing trace check

Executed `analyze_trace.py inspect` on `traces/PERF-110-device-manual-save-r5.trace`, retrying with authorized cache access after the sandbox denied Instruments' analysis cache. The current saved TOC still contains only:

- Run 1: 2026-10-12 09:33:12 +02:00, 32.710477 s, simulated iPhone 17 / iOS 27.0.
- Run 2: 2026-10-15 10:18:31 +02:00, 40.707846 s, the same simulator platform.

The previously requested search run 3 is absent. No run 2 tab-entry CPU totals were substituted for search evidence. The trace's binary is an earlier capture; HEAD here identifies the current diagnostic checkout, not that recorded binary. Key-to-result latency remains unavailable.

## Reproduce and retrieve samples

Run this diagnostic suite alone because recorder counters are process-wide. It is opt-in and skipped in ordinary test runs. `TEST_RUNNER_` forwards the opt-in to the test process; verify **one executed test and zero skips**, not just a successful command exit.

```sh
rtk proxy env TEST_RUNNER_PFT_SEARCH_BASELINE=1 scripts/xcb test -only-testing:PersonalFinanceTrakerTests/ActivitySearchBaselineTests
rtk proxy xcrun xcresulttool export diagnostics --path .build/Test.xcresult --output-path .build/activity-search-diagnostics
rtk rg 'PFT_SEARCH_BASELINE' .build/activity-search-diagnostics
```

Use a fresh diagnostic export directory on later runs. The quiet xcb log does not contain sample stdout; it is in the exported `StandardOutputAndStandardError.txt`. Export only the fixed `PFT_SEARCH_BASELINE` JSON lines when sharing. Raw host diagnostics, test results and traces remain local/ignored. Baseline artifacts are `.build/Test.xcresult`, `.build/activity-search-diagnostics`, and `.build/activity-search-5k-{samples,summary}.json`.

## Smallest next measurement and stopping criterion

First supply/save the existing search trace/run 3 and identify which step visibly stalls, plus device/build. Re-inspect the TOC, select that run explicitly, and analyze its final ten seconds as previously requested. Do not start another architectural experiment from whole-recording CPU totals.

Only if the saved segment cannot separate phases, use one focused capture: existing 5,000-transaction store on the target physical device, optimized Release/Profile build (the scheme's Profile action is Release), Time Profiler + Points of Interest, same instrumentation/settings. Record model/OS/build/dirty scope, locale, thermal state, launch arguments and first-vs-warm occurrence. Do not reseed the real store. The existing skip-lock flag is Debug-only; unlock before measurement. Preserve current nonseeding arguments, with a search-specific scenario name.

1. Open Activity and wait 10 s for launch/load work to settle; start recording.
2. Tap search to show the keyboard without typing, wait 3 s, and note any stall.
3. Type the non-sensitive fixture query `Coffee` at a stated cadence, wait 3 s; extend to `Coffee 4242`, wait 3 s; clear and wait 3 s. On a real ledger choose an agreed non-sensitive query with known expected results. Note the exact step and visible stall. Include a repeated sequence only if it changes the first-use vs everyday decision.
4. Leave 5 s idle, stop and **save** to a new local ignored trace such as `.performance-audit/measurements/traces/Activity-search-5k-target-r1.trace`. Return path and saved run number.
5. Query-request/generation, debounce-expiry, filtered-publication and superseded-work markers are still missing in production. If a marked repeat is required, add only opt-in boundary instrumentation before state mutation and use generation/counts without financial text; do not change filtering/cancellation behavior. Analyze main-thread stacks and intervals around all phases, including keyboard work before the first query marker. Frame presentation needs its own evidence.

Stop here: this baseline demonstrates no app-owned cause warranting optimization. Continue only with the missing user-symptom/device evidence and an agreed acceptance criterion; allow at most one causally motivated change and one comparable follow-up before reassessing.

No UI changes were made. Physical-device typing/keyboard/frame capture, light/dark, compact/wide, Dynamic Type and VoiceOver were not run; no UI or accessibility completion claim is made.

Final checks: the targeted test built and executed successfully; `git diff --check` passed; `graphify update .` completed and introduced no Git-status changes. All 16 pre-existing dirty files retained their captured hashes. The only additions are the opt-in diagnostic test and this Markdown/JSON measurement pair. No temporary production instrumentation or debug logs were added.

## Publication harness check — 2026-10-16

The unchanged harness passed alone in Debug-TEST on the isolated publication
checkout based on `8dbb9e4` plus the TEST contribution: one executed test, zero
failures/skips. The structured action log contains 24 unique records (rounds
0–5, broad/extend/miss/clear); each has 5,000 inputs and the expected
2,500/1/0/5,000 result count, with the asserted grouping/page/counter budgets.
This is a fresh harness/behavior check, not a comparable rerun of the timing
distributions above. Its samples and xcresult remain local under
`.build/pr230-two-commits/` and the verification checkout.

On current xcresulttool, if a separate console log is unavailable,
`get log --path <bundle> --type action` also exposes the fixed
`PFT_SEARCH_BASELINE` lines. Share only those synthetic records, not the full log.
