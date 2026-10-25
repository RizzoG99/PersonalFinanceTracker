#!/bin/bash
# PreToolUse(Bash): enforce CLAUDE.md git rules. Exit 2 = block, stderr goes to the agent.
CMD=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
block() { echo "git-guard: $1" >&2; exit 2; }

# No AI attribution in commit messages, PR/issue bodies or comments.
if printf '%s' "$CMD" | grep -qE 'git commit|gh (pr|issue) (create|edit|comment|review)' &&
   printf '%s' "$CMD" | grep -qiE 'co-authored-by:.*(claude|anthropic)|noreply@anthropic\.com|generated with.*claude|claude\.com/claude-code|🤖'; then
  block "remove the AI attribution (Co-Authored-By / 'Generated with Claude Code' / 🤖) — this repo's commits, PRs and comments carry none."
fi

valid='^(feature|fix|chore)/[a-z0-9][a-z0-9._-]*$'

# New branch names (checkout -b, switch -c, worktree add -b, branch <name>)
name=$(printf '%s' "$CMD" | sed -nE 's/.*(checkout -[bB]|switch -[cC]|worktree add .*-b|git branch) +([^ ;&|]+).*/\2/p' | head -1)
if [ -n "$name" ] && ! [[ "$name" =~ $valid ]] && [[ "$CMD" != *"git branch -"* ]]; then
  block "branch '$name' must be feature/<slug>, fix/<slug> or chore/<slug> (never worktree-*)."
fi

case "$CMD" in
  *"git commit"*)
    br=$(git branch --show-current 2>/dev/null)
    if [ "$br" = main ] && [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]; then
      block "committing on main in the primary checkout. Create a worktree + feature/fix/chore branch first."
    fi
    [ -n "$br" ] && [ "$br" != main ] && ! [[ "$br" =~ ^(feature|fix|chore)/[A-Za-z0-9._/-]+$ ]] && block "branch '$br' is not feature/*, fix/*, chore/*."
    ;;
  *"gh pr create"*)
    br=$(git branch --show-current 2>/dev/null)
    case "$br" in
      feature/*|fix/*)
        [[ "$CMD" == *PFT_SKIP_CHANGELOG=1* ]] && exit 0
        if git diff --quiet origin/main...HEAD -- CHANGELOG.md 2>/dev/null; then
          block "CHANGELOG.md has no new bullet under '## Unreleased'. Add one, or prefix the command with PFT_SKIP_CHANGELOG=1 if there is no visible effect."
        fi;;
    esac;;
esac
exit 0
