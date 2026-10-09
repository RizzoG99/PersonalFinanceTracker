---
name: pft-pr-lifecycle
description: Deliver a PersonalFinanceTracker issue or scoped change through an isolated worktree, verified evidence, an issue-linked pull request, and authorized post-merge cleanup.
metadata:
  scope: "PersonalFinanceTracker"
  inspiration_repository: "https://github.com/mattpocock/skills"
  inspiration_revision: "6fd947921b935b7e1e69293a200400f0fdd5c15f"
  inspiration_path: "skills/engineering/pr"
---

# PersonalFinanceTracker PR Lifecycle

Deliver the requested change without widening its scope, losing unrelated work, overstating evidence, or treating PR creation as permission to merge or release.

## Authority boundaries

Resolve the requested stopping point before acting:

- Implementation authorizes scoped local edits and proportionate verification.
- An explicit request to create a PR includes organized commits, push, PR creation, closing references, and normal issue/project wiring for the issues in scope.
- PR creation does not authorize merging.
- Cleanup requires a confirmed merge and an explicit cleanup request.
- Changelog work does not authorize `scripts/xcb release-notes`, TestFlight upload, tester assignment, or release.

If the user requested only a later phase, inspect the existing work and begin there. Do not redo completed work without evidence that it is stale or incomplete.

## 1. Pin the contract

1. Read `AGENTS.md`, the requested issue or specification, and any directly linked evidence.
2. Record the issue numbers, acceptance criteria, base branch, intended stopping point, and known verification limits.
3. Inspect `git status`, the current branch, and `git worktree list`. Preserve every unrelated tracked, untracked, IDE, generated, and main-checkout change.
4. Use live GitHub issue/project state when publication is in scope; do not trust cached field IDs or old issue status.

The contract is pinned when every requested outcome maps to an acceptance criterion or is explicitly marked out of scope.

## 2. Isolate the change

Before code edits, enter the requested worktree or create a dedicated one from the correct base. Use the repository's `feature/<slug>`, `fix/<slug>`, or `chore/<slug>` branch convention, including the issue number when one exists. A worktree directory name is not a branch name.

If intended edits already exist in another checkout, preserve that checkout and transfer only the scoped files or hunks. Never discard unrelated changes to recover the workflow.

The change is isolated when the working directory, branch, base, and intended files are unambiguous.

## 3. Implement against the contract

- Use the matching project skill when the task triggers one, including `$swiftui-pro` for materially changed UI and `$diagnosing-bugs` when the cause is uncertain.
- Keep user-facing English and Italian semantically aligned and add every new string to the localization catalog.
- Keep implementation, tests, documentation, and changelog changes scoped to the issue contract.
- Treat `graphify-out/` as ignored, worktree-local state. Never stage or publish it.

Do not advance because the code merely looks plausible. Advance when each implemented criterion has observable evidence.

## 4. Build the evidence ledger

For every acceptance criterion, record:

| Criterion | Evidence | Verdict |
|---|---|---|
| Expected behavior | Test, build, screenshot, inspection, or manual procedure | Verified, partial, or unverified |

Use `scripts/xcb` as defined by `AGENTS.md`. Start with the narrowest relevant tests, then run broader validation proportional to the change. Read the JSON test summary and confirm the expected tests actually ran; build success is not visual, accessibility, localization, or runtime evidence.

Test evidence is current only when it aligns with the PR's current HEAD. Record the HEAD SHA, command, runtime, and exact passed, failed, skipped, and expected-failure counts from the result bundle. Rerun after later commits or when the surviving artifact cannot be tied to the current source. Re-read the PR body after final QA: completed checks still described there as unverified leave the lifecycle evidence stale.

### SwiftData schema transitions

Classify persistent-schema risk from a tested transition, not from the shape of the diff alone. For every changed `@Model` or schema membership:

1. Identify the exact previously shipped schema and the proposed next schema.
2. Follow the existing `SchemaMigrationTests` pattern: write a representative on-disk store with the old schema, reopen it with the new schema, and verify unrelated financial records survive with their values and relationships intact.
3. Run the transition test on the deployment-baseline runtime when it is available. A passing test verifies that exact transition; simple additions or removals may be lightweight, while renames, type changes, and data transforms require explicit versioned-schema and migration-plan evidence.
4. Mark an untested or failing transition as an unresolved migration risk. A model-file deletion by itself is not evidence that reinstall or data loss is required.

Before publication:

- Run `git diff --check`.
- Review the full intended diff and `git status`.
- Confirm tests/builds from their actual results, not only exit status.
- Complete required light/dark, compact/wide, Dynamic Type, VoiceOver, and relevant-state checks, or name each unrun check.
- Add a tester-facing `CHANGELOG.md` Unreleased bullet for visible changes.
- Confirm unrelated and generated files are excluded.

The evidence gate passes only when every criterion has an honest verdict, every limitation is visible, and the PR description reflects the latest evidence.

## 5. Publish only when authorized

When commit, push, or PR creation is within the requested stopping point, read [references/publish.md](references/publish.md) and follow it completely. Stop before merge unless the user separately requests it.

## 6. Clean up only when authorized

After a confirmed merge and explicit cleanup request, read [references/cleanup.md](references/cleanup.md) and follow it completely.

## Completion report

Report the delivered scope, branch and worktree, commits and PR URL if created, acceptance-criterion verdicts, commands actually run, unverified checks, issue/project linkage, and remaining lifecycle state. Never claim an external action from an attempted or still-running command.
