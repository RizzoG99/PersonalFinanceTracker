---
name: pft-android-pipeline
description: Take a PersonalFinanceTracker Android task (parity capability, parity gap, or idea) through frozen-iOS analysis, one owner decision, a reviewed plan, red-first emulator tests, implementation, review, and publication.
---

# PersonalFinanceTracker Android task pipeline

The Android twin of `$pft-task-pipeline`, numbered step for step so the two stay aligned. Deliver one task end to end with a single human **gate**: the owner decides once, after the brainstorm, and everything after it runs autonomously up to publication. The GitHub issue is the **contract**: every step reads it and writes its outcome back to it.

Android work is held to **parity**: the frozen iOS app defines what the user can do, and Android proves it matches. The program rules (lifecycle, Definition of Done, difference policy, capability issue template) live in the body of #75; read it once per task, it is the single source.

Run the steps in order; each ends on its completion criterion. A later step that finds the contract wrong goes back to the step that owns it rather than working around it.

## Where the code is

The Android app lives in `Android/` (Kotlin, Compose, Room, DataStore). Check `git ls-tree origin/main Android`: while it prints nothing, the code lives only on `codex/android-native` (draft PR #146, worktree `.worktrees/android-native`), so the task branch starts from `codex/android-native`. That worktree may hold another agent's uncommitted work: read it, never edit it.

## Authority

- The gate (step 2) and **escalations** are the only moments for the owner. Escalate, with AskUserQuestion, only a genuine product question: one whose answer changes what the user sees or can do. A functional deviation from frozen iOS is always a product question (#75 difference policy). Everything technical, decide and record as a `D-xx` decision.
- Explain options in plain words, defining any jargon with an example, in the owner's language, before asking.
- Creating and editing issues, project fields, and commits on the task branch are in scope. Pushing and opening a PR are in scope only as the owner chose at the gate. Merging and Google Play releases are not.

## 0. Intake

- GitHub issue: read it with `gh issue view <n> --comments`, then its parent milestone tracker (#76–#82).
- Idea or defect without an issue: file it on the shape in #75's "Capability issue template".
  - New capability: title `[Android][M<k>][Parity <ID>] <promise>`, a sub-issue of its milestone tracker.
  - Defect in a verified capability: title `[Android][M<k>][Parity Gap] <what happens>`, with a *Gap identity* section naming the parent capability and its `AC-xx` (precedent: #130).

Make sure the issue is on the **Android Native** project (`gh project item-add 3 --owner RizzoG99 --url <issue>`) with Status, Roadmap phase, Area, Parity, Evidence set; read field and option ids live (`gh project field-list 3 --owner RizzoG99 --format json`).

Done when exactly one issue holds the task, it names its parent, and it is on the project.

## 1. Analysis

- **Frozen iOS functional analysis**: read the iOS source at the frozen commit named in #75 (`git show <frozen>:<path>`), never at today's `main`. Cover entry points, happy path, states (populated, empty, no results, loading, error, locked), data and calculation rules, localization and accessibility. Cite `file:line` at the frozen commit, and record what iOS does *not* do as carefully as what it does (#111 is the worked example).
- **Drift check**: diff the same paths between the frozen commit and `origin/main`. Each relevant change becomes a new parity item, an approved extension, or an explicit deferral.
- **Android inventory**: what exists in `Android/` today, with `file:line`. Orient with `graphify query` when the graph exists. Use `$diagnosing-bugs` for a gap whose cause is uncertain.

Done when every frozen behaviour in scope is stated with a citation and every Android difference is listed.

## 2. Brainstorm and gate

Present 2–3 genuinely different options with pros and cons and a recommendation (for a new or unclear capability, run `$feature-brainstorm` to get there). Propose:

- acceptance scenarios `AC-01..n`, each *Given … when … then …*, with deterministic fixtures and explicit expected values for money and dates, observable on a compact phone and a wide layout, including regressions the change could cause;
- every difference from frozen iOS as a `D-xx` row, typed functional or visual, with the decision you propose;
- how to publish: commits only on the task branch, a PR into `codex/android-native`, or a PR into `main` once `Android/` is there.

Ask the owner to pick the option, approve the scenarios and the functional deviations, and choose how to publish.

Done when the owner has decided all four.

## 3. Ticket

Rewrite the issue body on #75's capability template: keep the report, fill Parity identity (frozen iOS commit, Android comparison commit), User promise, Scope and non-goals, Frozen iOS functional analysis, the Android inventory, Acceptance scenarios, and the Differences and decisions table with the owner's approvals. Set Status to In Progress and Evidence to Contract ready.

Done when every template section is filled except Android implementation and evidence, Verification checklist, and Final verdict.

## 4. Plan

Create the worktree and branch (`fix/<n>-<slug>` or `feature/<n>-<slug>`, from the base in *Where the code is*). Write the plan to `.plan/<n>.md` in the worktree. `.plan/` must stay out of commits: if `git check-ignore -q .plan/x` fails (it does on `codex/android-native`, whose `.gitignore` predates it), append `.plan/` to `$(git rev-parse --git-common-dir)/info/exclude`. The plan names:

- each `AC-xx`'s test: JVM or instrumented, the class, the steps, the exact semantics queries, its capture cells, and which AC is expected to go **red** on today's code;
- every file to change and the change, including both `values/strings.xml` and `values-it/strings.xml` for new copy;
- side effects on behaviour that is not under test, and how each is covered or why it is accepted;
- Room schema changes and the migration test that proves them;
- the verification commands.

Read [references/parity-tests.md](references/parity-tests.md) before writing the test part.

Done when every AC maps to a test and every change to a file.

## 5. Plan critique

Run critic rounds with the mechanics and prompts in [`../pft-task-pipeline/references/critique.md`](../pft-task-pipeline/references/critique.md), substituting:

- "iOS repo" → "Android app under `Android/`; read `Android/README.md` and the issue's parent tracker too";
- the plan checklist → whether each AC test will actually work (semantics queries, locale and font-scale recreation, the PIN gate, first-run seeding, compact vs wide), whether the fix location is right, side effects on other callers, and any `D-xx` the plan silently introduces;
- the code-review checklist → the logic the task changes, coroutine scope and cancellation (a failure that escapes `viewModelScope` kills the process, #133), raw `Throwable.message` reaching the screen (#135), Room migrations, vacuous tests, and regressions in sibling capabilities.

Fix every BLOCKING finding in the plan and log each round in the plan's Review log, at most 3 rounds. After round 3, decide remaining technical findings yourself and record them as `D-xx`; escalate product questions as soon as they appear, in any round. Then publish a short plan to the issue and file out-of-scope problems as their own issues.

Done when the plan is on the issue and the last round either was APPROVE or its remaining findings are recorded as decided.

## 6. Red, then green

1. Write the AC tests and run them on the unchanged code. At least one AC must go red for the reason the task is about. If none does, record why as a `D-xx`, and check that some test covers the root cause.
2. Implement. For UI changes, read `.agents/skills/android-compose-pro/SKILL.md` and its `references/design.md` in the task worktree (the skill exists only on the Android branch, so it may not be invocable from this session), plus `Android/README.md`'s semantics rules.
3. Rerun until every AC test passes and every capture cell is written.

Set Evidence to Verifying when the first AC goes green.

Done when the JUnit XML for the task's classes shows `failures="0"` and `errors="0"` with the expected test count, on JVM and on the emulator.

## 7. Visual review

Open every capture cell the task produced (EN and IT, light and dark, compact and wide, default and large font scale) next to the matching frozen iOS screenshot. Check each against its AC's *then*, plus:

- information hierarchy and product identity equivalent to iOS (#75: visual differences are fine when these hold);
- nothing clipped or overlapping at large font scale or in Italian;
- the semantics dump: every control labelled, headings marked, status changes announced.

Done when every cell was checked and each problem is fixed or recorded as a `D-xx`.

## 8. Code review

Run critic rounds on the diff as in step 5. After every fix rerun step 6, and if the fix changes what is on screen, repeat step 7 for the cells that changed.

Done when the last round was APPROVE on the final diff, or its remaining findings are recorded as decided.

## 9. Full verification and publication

1. From `Android/`, run the four gates CI requires, one after another, in the background: `./gradlew :app:assembleDebug`, `:app:testDebugUnitTest`, `:app:lintDebug`, `:app:connectedDebugAndroidTest`. Read the counts from the JUnit XML, not the exit code. CI runs instrumentation on API 26 and 34; locally there is one AVD, so name its API level and leave the CI matrix as the only proof for the others.
2. Skip the `CHANGELOG.md` bullet: it feeds TestFlight only, and Android has no release-notes channel until #81 (precedent: #146 has none). A PR then needs `no-changelog` in its body for CI and `PFT_SKIP_CHANGELOG=1 gh pr create …` for the `git-guard.sh` hook.
3. Commit, then publish as the owner chose at the gate. For a PR, follow `$pft-pr-lifecycle` (its publish reference) with `Closes #<n>`, overriding it in three places: the base is the one chosen at the gate, the changelog rule is step 2's, and the project fields are project 3's.
4. Fill the issue's *Android implementation and evidence*, *Verification checklist*, and *Final verdict*: commits, the tests mapped to each `AC-xx`, counts, device and API level, and what was not run (physical device, TalkBack by hand, API levels). Set Evidence to Verified and Parity to Matched only when every AC passed and every cell was reviewed; the verdict text says "Matched with approved deviations" when any `D-xx` was approved (the project field has no such option). A capability the owner approved as Android-only or postponed at the gate takes Parity Platform-specific or Deferred instead. Otherwise set Evidence to Gap found, link the gap issue, and say why.

Done when the commits are published as chosen and the issue's verdict names them.

## Report

Summarise for the owner, in their language:
- the commits or PR, and the issues touched or filed;
- each `AC-xx`'s before/after;
- each `D-xx` and who approved it;
- the critic rounds;
- every limitation: anything not reproduced, not automated, or run only on the local AVD.
