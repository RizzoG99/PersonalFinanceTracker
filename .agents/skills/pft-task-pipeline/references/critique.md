# Critic rounds

A **critic** is the *other* agent, run headless and read-only, so a second model checks the work:
- Claude Code calls Codex.
- Codex calls Claude.

Critics only read: files, `rg`, `graphify`, `gh issue view`, and `git diff` / `git show` / `git log`. They never edit files, build, or run tests: only one agent runs a simulator or emulator.

## Running a round

Write the prompt to `.plan/<n>-<kind>-prompt-r<k>.md`, where `<kind>` is `plan` or `review`, then run the round in the background as one plain command from the worktree root:

```bash
scripts/critic codex <n> <kind> <k>    # Claude Code → Codex
scripts/critic claude <n> <kind> <k>   # Codex → Claude
```

It writes `.plan/<n>-<kind>-r<k>.md` and fails loudly if the prompt is missing or the critic wrote nothing. On a branch without `scripts/critic`, `git show origin/main:scripts/critic` shows the two underlying commands.

## Rounds and decisions

- Verify every BLOCKING finding against the cited file:line before acting on it. A finding you can disprove with evidence is answered in the plan's Review log, not applied.
- Fix every BLOCKING finding you confirm, log the round in the Review log, and run the next round. Stop at APPROVE, or after round 3.
- BLOCKING findings left after round 3:
  - **Technical**: decide yourself, applying the best-evidenced option. Record the disagreement in the issue's decision record (iOS: Decision log; Android: a `D-xx` row) and list it under the PR's Limitations.
  - **Product questions**: escalate to the owner as soon as one appears, in any round. Every `ESCALATE` finding you confirm is one.
- File out-of-scope problems a critic uncovers as their own issues.

## Plan critique prompt (round 1)

```
You are a plan critic for the PersonalFinanceTracker iOS repo (read AGENTS.md first). Read-only: do not edit files.

Review the plan in `.plan/<n>.md` against GitHub issue #<n> (`gh issue view <n>`), which is the contract. The Decision and the Acceptance scenarios were approved by the owner. Do not reopen them.

Rules:
- Every finding cites objective evidence: a file:line you read, or a command plus an excerpt of its output. If you can't verify a concern, drop it.
- Read files with your file-reading tool, or with `sed -n`/`cat` if you have none. Use the shell only to read: `rg`, `graphify query`, `gh issue view`, `git diff`, `git show`, `git log`.
- Paraphrase first: before any finding, write in 2–5 sentences what the plan changes and how the current code works, as the plan describes it. A part you cannot paraphrase, or whose paraphrase contradicts the issue, is BLOCKING.
- Check especially:
  - whether each scenario test will actually work: element queries and labels, focus and keyboard, first-run behaviour on a clean install, iPad layout, and background/foreground with the PIN lock;
  - whether the fix location is right: the right layer (View, ViewModel, model/repository) and the root cause rather than a local workaround;
  - whether it is the simplest change that meets every scenario: no speculative code or abstraction, and existing components, helpers and theme styles reused rather than rebuilt;
  - whether every file, type and function the plan says exists does exist and behaves as described (a contradiction with the code is BLOCKING), and every file is tagged Create, Modify or Delete;
  - whether the plan leaves any design choice to the implementer (a data shape, a new edge case, a dependency): each one is a finding;
  - side effects on other callers and states;
  - anything missing to meet every scenario on iPhone AND iPad.
- A finding that needs a different option than the approved Decision is `ESCALATE`, not `BLOCKING`.
- Stay on #<n>. Out-of-scope problems: one line each, at the end.

Output a markdown list, after the paraphrase. Each item gives:
- `BLOCKING`, `NON-BLOCKING` or `ESCALATE`;
- the finding;
- the evidence;
- the concrete change to the plan.

End with `VERDICT: APPROVE` if there are no BLOCKING items, otherwise `VERDICT: REVISE`.
```

## Code review prompt (round 1)

```
You are the code reviewer for the PersonalFinanceTracker iOS repo (read AGENTS.md first). Read-only: do not edit files.

Review this worktree's diff against its base: `git diff <base>...HEAD` plus uncommitted and untracked files. Check it against issue #<n> (`gh issue view <n>`) and the plan in `.plan/<n>.md`. The scenario run is green: <counts>.

Look for correctness bugs, and only those:
- the logic the task changes;
- Swift 6 concurrency;
- `knownAccessibilityIssues` entries broad enough to hide a NEW finding;
- vacuous tests, meaning assertions that pass without proving their scenario;
- regressions in the related issues named in the contract.

Every finding cites file:line and the evidence. Skip style nits.

Output a markdown list. Each item: `BLOCKING` or `NON-BLOCKING`, the finding, the evidence and the fix. End with `VERDICT: APPROVE` or `VERDICT: REVISE`.
```

## Later rounds

```
This is round <k> of the <plan critique | code review>. The rules and output format are the same as in `.plan/<n>-<kind>-prompt-r1.md`. Read that file first.

The previous findings are in `.plan/<n>-<kind>-r<k-1>.md`. The revision changed: <one line per change>.

Do two things:
1. Confirm each previous finding is resolved, or say why it is not. Cite evidence.
2. Report only NEW problems, focusing on what changed.

End with `VERDICT: APPROVE` or `VERDICT: REVISE`.
```
