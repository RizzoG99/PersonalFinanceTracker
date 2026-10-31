---
name: testflight-feedback
description: "Fetch TestFlight feedback, analyse it against the code, and file or merge GitHub issues on the iOS Native project."
metadata:
  scope: "PersonalFinanceTracker"
---

# TestFlight feedback triage

Every unresolved tester report ends in exactly one place: merged into the open issue that already covers it, filed as a new issue, discarded as unintelligible, or reported as already fixed. Nothing is decided from the comment alone; the code at the latest commit decides.

## 1. Fetch

Run `python3 .agents/skills/testflight-feedback/scripts/fetch_feedback.py --download <scratchpad>/shots`. It reads App Store Connect (credentials from `.env`, like `scripts/xcb`) and prints one JSON line per report not marked resolved in Xcode: `id`, `build`, `date`, `comment`, `screenshots`, and `tracked` (GitHub issues, open or closed, whose body cites the `feedbackIdentifier`). Screenshots land in the scratchpad (URLs expire) and can be opened with Read.

The list is complete when every line has a verdict from step 2.

## 2. Analyse before deciding

Run `git fetch` and read the code at the tip of the default branch; record the commit sha. Orient with `graphify query` / `rg`, then open the exact code path. Look at the screenshot when the comment leaves the screen or element unclear.

Resolve each doubt by reading code, running the targeted test (`scripts/xcb test -only-testing:...`), or reproducing the scenario; a verdict states which code or test shows it. Compare the report's build date with the merge date of any related fix.

Assign one verdict per report:

- **Already fixed**: the current code handles the scenario (cite file and test or commit). It goes in the final report; no issue.
- **Covered by an open issue**: add the report as a comment on that issue (build, id, quote, new detail). No new issue. A closed issue covering it counts only if the current code still fails; then reopen it with the evidence.
- **New**: file it (step 3).
- **Unclear**: ask the user together with all other unclear reports (AskUserQuestion, with the screenshot's content described). Still not understandable after their answer → discard and list it as discarded.

## 3. File

Filing is in scope when the user invoked this skill to file; otherwise show the titles first. One issue per report, in English, written like a functional analyst turning a customer report into a ticket. The body follows `.github/ISSUE_TEMPLATE/bug.md` (or `feature.md` for a request), which `$pft-task-pipeline` later completes:

- **Report** (*Problem* in `feature.md`): verbatim quote, build, full `feedbackIdentifier`, screenshot count. State what the tester did not say instead of guessing it.
- **Root cause** (*Functional analysis* in `feature.md`): the pre-analysis. Give the commit sha analysed, what was read or run, and what remains unverified. When the cause needs logs or a device, say so here.
- **Acceptance scenarios**: a draft list. Cover light/dark, iPhone/iPad, and Dynamic Type for UI work.
- Name related issues in the Summary.

Labels `bug` or `enhancement`, title prefix `[iOS]`, no AI attribution footer. Add each issue to the **iOS Native** project (`gh project item-add 4 --owner RizzoG99 --url <issue>`) and set Status=Todo, Priority (P0–P3), Area, Evidence=Unverified; read ids live with `gh project field-list 4 --owner RizzoG99 --format json`.

Attach a screenshot only when the issue is unintelligible without it. `gh` cannot upload images, so the file goes to `docs/feedback/ios-YYYY-MM/b<build>-<id8>.jpg` (the existing convention) and the issue links that path; this needs a `chore/` branch from a worktree and a commit, so ask the user first.

## 4. Final report

A table: report → outcome (new #N, comment on #N, already fixed, discarded) with the evidence for each. Close with the exact list of `feedbackIdentifier`s that can be marked resolved in Xcode (every report that is fixed, filed, or merged into an issue). Xcode stores that flag only in its local cache and App Store Connect has no field for it, so the user sets it in the Organizer.
