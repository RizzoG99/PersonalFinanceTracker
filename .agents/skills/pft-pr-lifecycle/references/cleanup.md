# Clean up a merged PersonalFinanceTracker PR

Read this only after the user explicitly requests cleanup.

## Prove the merge

1. Query the PR live and confirm it is merged, including `mergedAt` and the merge commit.
2. Record the exact worktree path and local/remote branch names.
3. Inspect the target worktree status. Stop if it contains uncommitted or untracked work that is not known to be disposable.

## Remove only the confirmed targets

1. Remove the exact merged worktree.
2. Delete the exact local feature/fix/chore branch.
3. Delete the exact remote branch only when requested or when it is the established cleanup scope.
4. Return to the primary checkout, preserve its unrelated changes, and run `git pull --ff-only` only when the checkout state makes that safe.

Never use a broad path, wildcard, unresolved variable, or repository root as a deletion target.

## Verify the final state

- The removed path is absent from `git worktree list`.
- The deleted local and remote branch names no longer resolve when deletion was in scope.
- The primary branch contains the merge commit or its descendant.
- Scoped issues/project items move to Done only after the merge is confirmed.
- Unrelated primary-checkout changes remain unchanged.

Report the exact paths and branches removed, whether the remote branch was deleted, the primary-branch update result, and anything intentionally retained.
