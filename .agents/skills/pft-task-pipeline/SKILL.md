---
name: pft-task-pipeline
description: Take a PersonalFinanceTracker task (GitHub issue, TestFlight feedback, or idea) through analysis, one owner decision, a reviewed plan, red-first scenario tests on iPhone and iPad, implementation, review, and a pull request.
---

# PersonalFinanceTracker task pipeline

Deliver one task end to end with a single human **gate**: the owner decides once, after the brainstorm, and everything after it runs autonomously up to an open pull request. The GitHub issue is the **contract** and the historical record: every step reads it and writes its outcome back to it.

Run the steps in order; each ends on its completion criterion. A later step that finds the contract wrong goes back to the step that owns it rather than working around it.

## Authority

- The gate (step 2) and **escalations** are the only moments for the owner. Escalate, with AskUserQuestion, only a genuine product question: one whose answer changes what the user sees or can do. Everything technical, decide and record in the Decision log.
- Explain options in plain words, defining any jargon with an example, in the owner's language, before asking.
- Creating issues, editing issues, project fields, commits on the task branch, push, and the PR are in scope. Merging, releasing, and TestFlight are not.
- Before publishing, if the branch is stacked on another unmerged branch, ask how to publish (stacked PRs or one PR).

## 0. Intake

- GitHub issue: read it with `gh issue view <n> --comments`.
- TestFlight feedback: triage that one report with `$testflight-feedback`.
  - If it files a new issue, continue with that issue.
  - If the report is covered by an existing issue, continue with that issue.
  - If the report is already fixed, stop and report the evidence; there is no task.
- Idea: create the issue from `.github/ISSUE_TEMPLATE/feature.md` (or `bug.md`), title prefix `[iOS]`.

Make sure the issue is on the **iOS Native** project (`gh project item-add 4 --owner RizzoG99 --url <issue>`) with Status, Priority, Area, Evidence set; read field and option ids live (`gh project field-list 4 --owner RizzoG99 --format json`).

Done when exactly one issue holds the task and is on the project.

## 1. Analysis

- **Bug**: find the mechanism. Orient with `graphify query`, then read the code. Use `$diagnosing-bugs` when the cause is uncertain.
- **Feature, or a bug that exposes a gap in how a feature is specified**: fill the *Functional analysis* section, which both templates have (in `bug.md` it is optional). Cover prerequisites, affected screens and models, states (empty, error, first run, Hide amounts, locked), data and privacy, and iPhone vs iPad.

Done when the root cause is stated with file:line, or every functional gap is listed as an answered fact or an open question.

## 2. Brainstorm and gate

Present 2–3 genuinely different options with pros and cons and a recommendation (for a new or unclear feature, run `$feature-brainstorm` to get there). Propose acceptance **scenarios** S1..Sn, each *Given … when … then …*, observable on screen, on iPhone and iPad, including regressions the fix could cause. Ask the owner to pick the option and approve the scenarios.

Done when the owner has chosen an option and approved the scenario list.

## 3. Ticket

Rewrite the issue body on the shape of `.github/ISSUE_TEMPLATE/<bug|feature>.md`: keep the report, fill root cause or functional analysis, Decision (with rejected options), the approved scenarios, and a dated Decision log entry. Set the project Status to In Progress.

Done when every template section is filled except Plan and Evidence.

## 4. Plan

Create the worktree and branch (`fix/<n>-<slug>` or `feature/<n>-<slug>`, from `main` unless the task depends on unmerged work). Write the plan to `.plan/<n>.md` in the worktree; `.plan/` is gitignored, so it never gets committed. The plan names:

- each scenario's test: class `<Topic>ScenarioTests`, the steps, the exact element queries, and which scenario is expected to go **red** on today's code;
- every file to change and the change;
- side effects on behaviour that is not under test, and how each is covered or why it is accepted;
- the verification commands.

Read [references/scenario-tests.md](references/scenario-tests.md) before writing the test part.

Done when every scenario maps to a test and every change to a file.

## 5. Plan critique

Run critic **rounds** as in [references/critique.md](references/critique.md). Fix every BLOCKING finding in the plan and log each round in the plan's Review log. Run rounds until the verdict is APPROVE, at most 3.

If BLOCKING findings remain after round 3:
- **Technical** findings: decide yourself. Apply the best-evidenced option, and record the disagreement in the Decision log and later in the PR's Limitations.
- **Product questions**: escalate. Escalate a product question as soon as it appears, in any round.

Then publish a short plan to the issue's Plan section, plus a Decision log entry for anything the critique changed. File out-of-scope problems the critique uncovered as their own issues.

Done when the Plan section is published and the last round either was APPROVE or its remaining findings are recorded as decided.

## 6. Red, then green

1. Write the scenario tests and run `scripts/xcb scenarios <Class>` on the unchanged code. At least one scenario must go red for the reason the task is about. If none does, record why (for example, device-only timing) in the Decision log, and check that some test covers the root cause.
2. Implement. Use `$swiftui-pro` for UI changes.
3. Rerun until every scenario passes on all five passes. Each new accessibility finding is either caused by the change (fix it) or pre-existing (file an issue per cause, then add an exact-label entry to `knownAccessibilityIssues`).

Done when `scripts/xcb scenarios <Class>` reports `"result": "Passed"` and every pass's `passed` equals its `total`.

## 7. Visual review

Open the screenshots in `.build/scenarios/shots/` for every scenario: iPhone light, dark and AX-XXXL, and iPad light and dark. Check each against its *then*, plus:

- app-theme consistency in light and dark;
- nothing clipped or overlapping at large text sizes;
- the iPad layout;
- the contrast reports (`S*-contrast-*.txt`): report-only, but flag anything this change made worse.

Done when every scenario screenshot was checked and each problem is fixed or recorded.

## 8. Code review

Run critic rounds on the diff as in [references/critique.md](references/critique.md), with the same round limit and decision rule as step 5. After every fix:
- rerun step 6's command;
- if the fix changes what is on screen, repeat step 7 for the screenshots that changed.

Done when the last round was APPROVE on the final diff, or its remaining findings are recorded as decided.

## 9. Full verification and PR

1. Run `scripts/xcb scenarios`, which is the regression run over every scenario class, then `scripts/xcb test`. Run them in the background, one after the other, and read the counts, not the exit code.
2. Add the `CHANGELOG.md` Unreleased bullet for a visible change.
3. Commit, push, and open the PR by following `$pft-pr-lifecycle` (its publish reference), with `Closes #<n>`. The Evidence table lists each scenario: red before or not, green after, and which screenshots were reviewed.
4. Fill the issue's Evidence section (PR, commit, counts, what was not reproduced or not automated). Set project Evidence to Verified only when every scenario passed on all five passes and its screenshots were reviewed. Otherwise leave it at Fix in progress and say why.

Done when the PR is open and the issue's Evidence names it.

## Report

Summarise for the owner, in their language:
- the PR and the issues touched or filed;
- each scenario's before/after;
- the critic rounds;
- every limitation: anything not reproduced, not automated, or flaky.
