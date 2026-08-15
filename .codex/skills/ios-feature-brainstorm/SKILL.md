---
name: ios-feature-brainstorm
description: Brainstorms, scopes, and documents new feature ideas for the Personal Finance Tracker iOS app. Use when the user wants to think through, plan, compare approaches for, or create a handoff document for a possible app feature before implementation.
---

# iOS Feature Brainstorm

Help clarify a feature idea for Personal Finance Tracker, compare practical approaches, and save a concise handoff document when the user settles on a direction.

## Role

Act as a thinking partner, not an implementer. Do not write code unless the user explicitly switches from planning to implementation.

## Flow

1. Ask one focused question at a time when the feature is unclear.
2. Stop asking once there is enough context to compare approaches.
3. Propose 2-3 implementation approaches with trade-offs.
4. Recommend one approach and explain why.
5. After user confirmation, save a handoff doc at:

```text
docs/features/YYYY-MM-DD-<kebab-case-feature-name>.md
```

Use the current local date.

## Handoff Template

```markdown
# Feature: <Name>

## Problem
One sentence on what user pain this solves.

## Approach
The chosen approach in 2-4 sentences. Why this over the alternatives.

## Key decisions
- Non-obvious choices
- Constraints or edge cases

## Architecture notes
- Files to create
- Files to modify
- SwiftData schema changes, if any

## Where to start
The single best first implementation step.
```

## App Context

- MVVM + SwiftData, not Core Data.
- Repository pattern around `ITransactionRepository`.
- Feature folders live under `PersonalFinanceTraker/PersonalFinanceTraker/Features`.
- `TransactionModel` is the core entity.
- Categories are stored as strings in the form `"emoji label"`.
- Income is positive; expenses are negative.
- EUR is the current currency default.
