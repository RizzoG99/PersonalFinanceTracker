# Critic rounds

A **critic** is the *other* agent, run headless and read-only, so a second model checks the work:
- Claude Code calls Codex.
- Codex calls Claude.

Critics read code and run `rg`, `graphify` and `gh issue view` only. They never edit files, build, or run tests: only one agent runs simulators.

## Running a round

Write the prompt to `.plan/<n>-<kind>-prompt-r<k>.md` and the answer goes to `.plan/<n>-<kind>-r<k>.md`, where `<kind>` is `plan` or `review`. Run it in the background and wait for the output file.

Claude Code → Codex:

```bash
codex exec -s read-only -C <worktree> -o .plan/<n>-<kind>-r<k>.md - < .plan/<n>-<kind>-prompt-r<k>.md
```

Codex → Claude:

```bash
claude -p --permission-mode plan --allowed-tools "Read,Grep,Glob,Bash(rg:*),Bash(graphify:*),Bash(gh issue view:*),Bash(git diff:*)" \
  < .plan/<n>-<kind>-prompt-r<k>.md > .plan/<n>-<kind>-r<k>.md
```

Verify every BLOCKING finding against the cited file:line before acting on it. A finding you can disprove with evidence is answered in the Review log, not applied.

## Plan critique prompt (round 1)

```
You are a plan critic for the PersonalFinanceTracker iOS repo (read AGENTS.md first). Read-only: do not edit files.

Review the plan in `.plan/<n>.md` against GitHub issue #<n> (`gh issue view <n>`), which is the contract. The Decision and the Acceptance scenarios were approved by the owner. Do not reopen them.

Rules:
- Every finding cites objective evidence: a file:line you read, or a command plus an excerpt of its output. If you can't verify a concern, drop it.
- Read files with your file-reading tool. Use the shell only for `rg`, `graphify query` and `gh issue view`.
- Check especially:
  - whether each scenario test will actually work: element queries and labels, focus and keyboard, first-run behaviour on a clean install, iPad layout, and background/foreground with the PIN lock;
  - whether the fix location is right;
  - side effects on other callers and states;
  - anything missing to meet every scenario on iPhone AND iPad.
- Stay on #<n>. Out-of-scope problems: one line each, at the end.

Output a markdown list. Each item gives:
- `BLOCKING` or `NON-BLOCKING`;
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
