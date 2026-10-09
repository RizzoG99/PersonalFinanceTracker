---
name: retro
description: "Conduct a retrospective on a coding session."
license: MIT
metadata:
  upstream_repository: "https://github.com/mattpocock/skills"
  upstream_revision: "6fd947921b935b7e1e69293a200400f0fdd5c15f"
  upstream_path: "skills/engineering/retro"
---

The user has asked for a **retrospective**. Suggest evidence-backed improvements to the coding environment so the same failure or friction is less likely in future runs. A retro proposes changes; it does not authorize editing steering files, hooks, CI, or external systems.

## Steps

1. Read `../writing-for-agents/SKILL.md`. If a candidate changes a skill or its invocation policy, also read `../writing-for-agents/SKILL-MECHANICS.md`.

2. Define the evidence boundary. Default to the current session and repository. If the user identifies another session, read only its specified or directly linked logs and artifacts. Do not search unrelated personal or global logs without explicit permission.

3. Establish the repository baseline before calling something missing or broken: inspect `AGENTS.md`, `CLAUDE.md`, relevant project skills and docs, `scripts/xcb`, available Xcode Cloud configuration, other tracked CI, and the current Git state. Absence of `.github/workflows` alone is not evidence that CI is absent.

4. Look for candidates for improvement in these categories.

- **Navigation**: how easy was it for the agent to find the right files? Are there hidden dependencies between files? Would a **navigation pointer** make it easier? _Use when_ the session took a long time to find a piece of information.
- **Automated checks**: could an existing or proportionate new check catch the demonstrated error? Inspect the real build, test, lint, hook, and CI paths before recommending another one. Prefer repairing an unwired or misleading check to adding a parallel system.
- **Steering and standards**: should a project instruction, skill, or review criterion be clarified, moved behind a pointer, or replaced with a deterministic check? Put mechanical rules in tooling when the maintenance cost is justified; keep genuine judgment calls in the smallest existing project document that reaches the reviewer.
- **Skill boundaries**: did a skill trigger too broadly, omit a required resource, or conflict with repository workflow? Prefer a narrow correction to accumulating universal rules.
- **Tool economy**: did the agent make expensive tool calls that could be streamlined? Is there any custom tooling (CLI's, MCP's) that is particularly token-inefficient? _Use when_ the agent made an expensive tool call.
- **No-ops and sediment**: look for duplicated, stale, or behavior-neutral instructions in project steering files. Preserve unexplained user edits and distinguish observed no-ops from stylistic preferences.
- **Information access**: look for opportunities to increase the agent's access to information. Teeing dev server logs, readonly access to third-party services. _Use when_ a crucial piece of information was not available to the agent.

5. Present candidates in order of severity. For each, cite the evidence, explain the recurrence it prevents, name the smallest proposed target, state cost or tradeoff, and describe how the improvement would be verified. Separate confirmed findings from hypotheses. If there are no material candidates, say so.

## Reference

### Implementation vs Review

Treat implementation and review as two stages even when the same agent or a human performs both. The implementation stage has the most **context pressure** because it explores, writes code, and debugs failures.

The review stage starts from the diff and originating requirement, so it can carry judgment-heavy standards without burdening implementation context.

Put judgment-heavy review criteria in the review stage. Keep safety-critical execution constraints available at the point of action.

### Files

You have access to several files in the repo:

- `CLAUDE.md`/`AGENTS.md`: these files are pushed to the context window of any agent working in this repo. They should be used incredibly sparingly, usually only for **navigation pointers** to other files.
- `CODING_STANDARDS.md`: use it only if the repository already adopts it or the user approves introducing it; prefer existing project skills and docs first.
- Docs: use docs as references files, pointed to by other files. Look for existing docs before writing new ones.
- Skills: use skills for docs (since their description goes into the agent's context window), or for user-invoked commands. Follow the advice in the `writing-for-agents` skill.
