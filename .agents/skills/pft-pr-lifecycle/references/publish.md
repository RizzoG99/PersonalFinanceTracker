# Publish a verified PersonalFinanceTracker PR

Read this only when commit, push, or PR creation is authorized.

## Preflight

1. Run `gh auth status` before the final commit/publish sequence.
2. Recheck the live issue state, base branch, current worktree, current branch, `git status`, intended diff, and evidence ledger.
3. Confirm the visible-change changelog rule is satisfied.
4. Resolve current GitHub Project field and option IDs live before editing project fields.

Stop if authentication is invalid, the base or branch is ambiguous, required evidence is missing, or unrelated files cannot be separated safely.

## Commit

- Stage explicit intended files; never use a broad stage that can capture unrelated work.
- Group commits by responsibility when the change has separable concerns.
- Write factual commit messages without agent attribution or self-reference.
- Inspect the staged diff before every commit.

## PR body

Use the smallest visual that clarifies the change; omit one when prose or a short table is clearer.

```markdown
## Summary

<what changed for the user and why>

## Evidence

| Requirement | Before | After | Verdict |
|---|---|---|---|
| <acceptance criterion> | <failing behavior or prior state> | <test, screenshot, or observed result> | Verified / Partial / Unverified |

## Testing

- `<exact command>` — <result>

## Merge Risk

- **Reversibility:** Easy / Moderate / Difficult
- **Blast radius:** <affected features, data, or platforms>
- **Rollback:** <how to reverse safely>

## Limitations

- <unrun visual, accessibility, device, localization, or CI check; omit section when empty>

Closes #<issue>
```

Use one `Closes #<issue>` line for every issue the diff actually satisfies. Add the closing references in the initial PR body; adding them after merge does not retroactively close issues.

Create multiline bodies through a safely written body file passed to `gh pr create --body-file`; do not interpolate Markdown containing shell syntax into a command string.

## Publish and verify

1. Push the exact branch and create the PR against the pinned base.
2. Inspect the completed commands before reporting success.
3. Verify with `gh pr view --json url,state,baseRefName,headRefName,closingIssuesReferences`.
4. Update the scoped issue comments and project fields required by the repository workflow. Keep `Status` and `Evidence` honest: an open PR is not a merged change, and unrun human checks remain unverified.
5. Check CI when requested or required for the stopping point. A pending check is pending, not passing.

PR publication is complete only when the remote branch, PR URL, base/head, and expected closing references are all confirmed.
