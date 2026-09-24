# iOS TestFlight feedback programme — progress & handoff

**Read this first when resuming.** One Claude session per batch: start fresh,
read this file, do one batch, update this file, stop. Carrying all batches in a
single session costs repeated context compactions and is the main budget sink.

- Plan of record: `~/.claude/plans/check-the-feedbacks-about-sparkling-babbage.md`
- Analysis reports: `docs/feedback/ios-2026-09/analysis/NN-*.md`
- Screenshots: `docs/feedback/ios-2026-09/b<build>-<shortid>.jpg` — committed on
  **PR #163**, which needs merging so the image links inside the issues resolve.

## Status

| Step | State |
|---|---|
| 0–2 evidence, repro check, board | done |
| 3 file issues #148–#162 | done |
| 4 analysis agents (one per issue) | done, every claim re-verified in the main session |
| 5 fix batches | **batch 1 done (PR #164); batch 2 fixed on `worktree-feedback-batch2-categories`, PR not opened yet; batches 3–8 pending** |

## Issues

| # | Title | Pri | Area | Report | Batch |
|---|---|---|---|---|---|
| 148 | Bulk category update after "select all" rewrites every outgoing transaction | P0 | Transactions | 01 | 1 ✅ PR #164 |
| 149 | CSV-created category missing from transaction detail and Settings → Categories | P1 | Import/Export | 02 | 2 ✅ branch |
| 150 | Category search matches the stored English key, not the localised name | P1 | Categories | 03 | 2 ✅ branch |
| 153 | Category icons fall back to a generic glyph in trends and the list filter | P2 | Categories | 08 | 2 ✅ branch |
| 151 | Hide amounts does not cover the daily-habit card (and credit cards) | P1 | Security | 04 | 3 |
| 152 | Recurring rules with no occurrence yet are untappable and drawn as disabled | P1 | Transactions | 05 | 4 |
| 155 | Selection mode: no way to create a trip when none exists | P2 | Trips | 06 | 5 |
| 156 | Long-press on a trip opens the detail sheet and enters selection mode | P2 | Trips | 06 | 5 |
| 157 | Selection mode: cannot tell a transaction is already part of a trip | P2 | Trips | 06 | 5 |
| 160 | Trip transaction rows do not match the Dashboard / list row layout | P3 | Trips | 13 | 5 |
| 154 | Two insight charts read as contradictory; the line falsely shows a decline | P2 | Insights | 07 | 6 |
| 158 | Theme change does not update the nav-bar close button until the sheet is reopened | P2 | UI | 11 | 7 |
| 159 | iPad: the filter-chips band does not match the app background | P3 | UI | 12 | 7 |
| 161 | Budgets screen: no income section, "No limit" wording, jumpy focus, dead space | P3 | Budgets | 14 | 8 |
| 162 | Dashboard suggestions surface recurring transactions instead of habitual daily spends | — | Insights | — | parked `enhancement`, no fix |

**Batch 5 (trips) branches off `feature/travel-groups` @ `a1f9e22`, not `main`** —
that feature is unmerged. Those four issue bodies open with a scope blockquote.

## Board — project #4 `iOS Native`, owner RizzoG99

```
project  PVT_kwHOBUGapM4BkRxg
Status   PVTSSF_lAHOBUGapM4BkRxgzhjC6Pc  Todo f75ad846 · In Progress 47fc9ee4 · Done 98236657
Priority PVTSSF_lAHOBUGapM4BkRxgzhjC6Wc  P0 d6b7ff8b · P1 2bc2164e · P2 bb4dccd6 · P3 c8a5a999
Area     PVTSSF_lAHOBUGapM4BkRxgzhjC6Wg  Transactions 6b3a3979 · Categories 8d12fc32 · Insights 1e8a0b45 ·
                                         Budgets 532eab05 · Import/Export d85f56f4 · Trips 3048f291 ·
                                         Security c58a1b9e · UI 4e7100cc · Quality e94466e7
Evidence PVTSSF_lAHOBUGapM4BkRxgzhjC6Xc  Unverified c66ab965 · Analyzed 26257928 ·
                                         Fix in progress a6deca7c · Verified 28f04847
```

Item IDs: `gh project item-list 4 --owner RizzoG99 --format json --limit 30`,
match on `content.number`. Edit with
`gh project item-edit --id <itemID> --project-id PVT_kwHOBUGapM4BkRxg --field-id <fieldID> --single-select-option-id <optID>`
(needs `dangerouslyDisableSandbox: true`).

Transitions per batch: Evidence `Analyzed` → `Fix in progress` → `Verified`;
Status `Todo` → `In Progress` → `Done` **only once the PR merges**.
#148 is currently Evidence=Verified, Status=In Progress (PR #164 open).

## Per-batch procedure

1. `EnterWorktree` — never commit on `main` in the primary checkout.
2. Dispatch one fix agent per issue with: the issue, its analysis report, the
   screenshot, and the two closest existing screens to follow. Any user-facing
   view change runs `$swiftui-pro` first and clears its quality gate.
   **Tell the agent to write its report to a file and return ≤5 lines** —
   agent prose landing in the main context is what drives compaction.
3. Main session reviews the diff. Do not close on an agent's self-report.
4. Prove it: run the new test red against base, then green. One
   `scripts/xcb test` per batch, not per issue.
5. `CHANGELOG.md` `## Unreleased` bullet in tester language.
6. Comment on the issue with evidence, open the PR, move the board.
7. Update this file, then stop.

## Hard-won facts — do not relearn these

- **Verify agents.** 5 of 13 dispatched agents made false claims. The batch-1
  fix agent never ran the tests, misdiagnosed the root cause, and introduced a
  chip-row regression no test of its own covered. The mandated main-session
  review is what caught it.
- **"The environment blocked the test suite" is false.** `scripts/xcb test`
  needs `dangerouslyDisableSandbox: true` — the Bash sandbox blocks
  CoreSimulatorService. Same for GitHub/Apple TLS, `~/Library`, keychain.
- **`scripts/xcb test` exits 0 on a compile failure.** Judge by
  `totalTestCount` and `failedTests`, never the exit code. (It does exit 65 on
  a genuine test failure.)
- **Full-suite baseline: 624 total / 621 passed / 0 failed / 3 skipped.**
- Run builds and tests in the background plus a `Monitor` until-loop.
- Per-test names are absent from `.build/test.log` under `-quiet`. To confirm a
  named test ran:
  `xcrun xcresulttool get test-results tests --path .build/Test.xcresult --compact`.
- No parallel testing on this Mac (`-parallel-testing-enabled NO` in `scripts/xcb`).
- **Context hygiene:** read file slices with `sed -n 'X,Yp'`, not the Read tool —
  whole-file Read results are re-injected verbatim on every resume. Grep the test
  JSON for the four fields you need rather than dumping it.
- `graphify query` is mandatory before a raw grep (PreToolUse hook), even when
  its answer turns out useless.
- rtk's output compression is display-only and mangles Swift source (drops `=`
  and `?`). Never author a `sed`/`python` patch pattern from rtk-rendered text.

## Batch 2 — what happened (read before batch 3)

Branch `worktree-feedback-batch2-categories` off `83bc9db`. 10 files,
+184 − 10. `CHANGELOG.md` bullets written. Issue comments posted with the
evidence. Board: all three Evidence=Verified, Status=In Progress.
**The PR is not opened** — the standing rule is to commit only when the user
asks, so that call is theirs.

- **No fix agents were dispatched.** Step 2 says to; this session implemented
  the three fixes directly. Reasons: the session instructions forbid calling
  agents unless the user asks, the 5-of-13 false-claim rate above, and the
  diagnoses were already complete in context. Recorded as a deviation, not a
  precedent.
- **#149's root cause is not the one in `analysis/02`.** The report blamed a
  name+type match failure in `confirmImport` Step 3; every variant of that was
  disproved. Real cause: `selections[csv]` was never `__new__`, via two leaks
  (sentinel written only on the sheet's Save; a saved import profile
  overwriting the choice). Leak 2 is test-covered red→green. **Leak 1 is
  read-verified only** — `configureNewCategory` / `isSavableWithoutEditing`
  are `private` members of a SwiftUI `View`. **A manual CSV import run is
  still owed.**
- **#150 needs a localized run to be observable.** `scripts/xcb test
  -testLanguage it -testRegion IT`; in English the string catalog is the
  identity. Proven red (`filteredItems.count → 0`) then green.
- **#153's visual checks could not be run** — light/dark, Dynamic Type,
  compact/wide, VoiceOver. Declared unverified in the issue comment, not
  claimed. `SpendingInsightService.swift:161` (`habitObservations` streak
  icons) is a third stale-icon site, deliberately out of scope — worth its
  own issue.
- Full suite on the branch: **629 total / 626 passed / 0 failed / 3 skipped**.
- `graphify-out/*` is dirty in this worktree and is **not** part of the
  change. Exclude it from any commit.

## Open question for the user

Data recovery for testers whose transactions #148 already rewrote — not built,
not scoped. The in-app undo only survives the session it was armed in.
