---
name: ios-feature-brainstorm
description: >
  Use this skill when the user wants to brainstorm, plan, or think through a new feature for the
  Personal Finance Tracker iOS app — even if they just say "I want to add X", "what if we had Y",
  or "let's think about Z". This is a lightweight thinking-partner skill: it clarifies the idea,
  explores a couple of approaches, and saves a concise handoff document so the design can be
  picked up in a new conversation without losing context. Trigger proactively any time a feature
  idea is mentioned, not just when the user explicitly asks to brainstorm.
---

# iOS Feature Brainstorm

Help the user think through a new feature for the Personal Finance Tracker app, then save a concise
handoff document so the idea can be continued in a future session.

## What you are doing

You're a thinking partner, not an implementer. Your job is to help the user clarify what they want
to build, surface the interesting design decisions, and produce a clear written summary — not to
write any code. Keep the whole conversation tight; this should feel like a quick design chat, not a
formal process.

## The flow

**Step 1 — Understand the idea**
Ask one focused question at a time to understand:
- What problem does this feature solve for the user?
- What is the expected UX? (where does it live, how is it triggered)
- Any constraints or "must haves" in mind?

One question per message. Stop as soon as you have a clear enough picture — don't over-interrogate
simple ideas.

**Step 2 — Propose 2–3 approaches**
Once you understand the idea, present 2–3 ways it could be implemented. For each, note the main
trade-off and keep it brief (2–3 sentences). Give a clear recommendation and explain why.

Factor in the existing architecture:
- MVVM + SwiftData (not CoreData)
- Repository pattern (`ITransactionRepository`)
- Feature-based folder structure under `/Features`
- `TransactionModel` is the core entity; categories are stored as strings ("emoji label")
- Sign convention: income positive, expenses negative

**Step 3 — Save the handoff doc**
Once the user confirms an approach (or says "looks good"), write a Markdown file to:
```
PersonalFinanceTracker/docs/features/YYYY-MM-DD-<kebab-case-feature-name>.md
```
Create the `docs/features/` folder if it doesn't exist.

## Handoff document structure

```markdown
# Feature: <Name>

## Problem
One sentence on what user pain this solves.

## Approach
The chosen approach in 2–4 sentences. Why this over the alternatives.

## Key decisions
- Bullet list of non-obvious choices made during brainstorming
- Any constraints or edge cases called out

## Architecture notes
Where this fits in the existing codebase:
- Files to create (e.g., new View, ViewModel, Model, Repository method)
- Files to modify
- SwiftData schema changes, if any

## Where to start
The single best first step to begin implementation.
```

Keep each section short. The goal is to give a future session enough context to start building
without re-litigating the design.

## Principles

- One question at a time — don't pile up multiple questions in one message
- Prefer multiple-choice questions when there are clear options
- YAGNI: if an idea is out of scope, say so and suggest deferring it
- Stay grounded in the existing app — propose things that fit the current patterns
- Don't write any code, don't start implementing — just design and document
