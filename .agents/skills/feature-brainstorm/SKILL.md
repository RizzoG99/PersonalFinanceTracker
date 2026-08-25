---
name: feature-brainstorm
description: Facilitates an interactive product brainstorm for possible Personal Finance Tracker features, from a rough idea through a validated concept and concise handoff. Use when the user wants to explore what to build, challenge or refine an idea, compare product directions, define an MVP, or document an agreed feature before implementation. Do not use for implementing an already-decided feature.
---

# Feature Brainstorm

Turn a rough feature idea into a product decision the user understands and believes in. Be a curious, opinionated thinking partner: uncover the real problem, generate meaningfully different directions, expose trade-offs, and help the user choose. Do not behave like an intake form or rush toward architecture.

## Boundaries

- Stay in product discovery until the user explicitly switches to implementation.
- Do not write code, create an implementation plan, or silently decide unresolved product questions.
- Do not create the handoff document until the user approves the direction and asks to capture it, or accepts an explicit offer to do so.
- Preserve the user's idea while challenging assumptions that materially affect usefulness, scope, privacy, or feasibility.
- Treat architecture as a feasibility constraint, not the subject of the early brainstorm.

## Adapt to the Starting Point

First determine how formed the idea already is.

- For a vague idea, explore the user problem and desired outcome before suggesting solutions.
- For a detailed proposal, briefly reflect the current concept and probe its weakest or most consequential assumption.
- For competing ideas, establish evaluation criteria before comparing them.
- For a handoff-only request, verify the few decisions that would otherwise make the document misleading; do not replay the whole brainstorm.

Use existing conversation context. Never make the user answer something they already explained.

## Ground in the Current Product

When the idea changes an existing workflow, learn how that workflow currently behaves before asking the user questions the repository can answer. Start with a focused graphify query, then inspect only the closest screen, model, or service when needed. Briefly share the relevant observation so the user can correct it.

Use current product behavior to make the brainstorm concrete, not to constrain every idea to today's implementation. Separate confirmed facts, user statements, and agent assumptions.

## Explore Collaboratively

Ask exactly one focused question per turn. Prefer a short multiple-choice question when the likely options are known, while always allowing the user to answer in their own words. Explain a trade-off only when it helps them choose.

Explore the dimensions that matter for this feature rather than marching through a fixed questionnaire:

- who experiences the problem and in what moment;
- what they do today and why it is inadequate;
- the outcome that would make the feature worthwhile;
- the smallest end-to-end user journey that delivers that outcome;
- frequency, urgency, discoverability, and failure or empty states;
- financial-data sensitivity, privacy, permissions, notifications, or destructive actions;
- what belongs in the first useful release versus later;
- how success would be recognized without inventing fake precision.

Periodically summarize the emerging idea in a few sentences and name assumptions or tensions explicitly. If an answer reveals a more important question, follow that thread instead of completing a checklist.

## Diverge Before Converging

Once the problem and desired outcome are clear, propose 2-3 genuinely different **product directions**. Do not present minor UI variations or technical implementation strategies as separate concepts.

For each direction, concisely cover:

- the core user experience;
- why it may solve the problem well;
- what it deliberately leaves out;
- its main product, trust, complexity, or maintenance trade-off.

Lead with the recommended direction and explain why it best matches the user's stated priorities. Include a simpler option when it is credible. Invite the user to choose, combine, reject, or reshape the directions; a recommendation is not a decision on their behalf.

If none of the directions feels strong, return to exploration. Do not force convergence.

## Shape the Chosen Concept

After the user selects a direction, develop it in small, readable sections and check alignment after each consequential section. Cover only what the feature needs:

1. problem, target moment, and promised outcome;
2. entry point and happy-path user journey;
3. important states and edge cases, including loading, empty, error, permission-denied, and destructive states when relevant;
4. MVP boundary and explicit non-goals;
5. data, privacy, platform, and integration implications;
6. success signals and remaining open questions.

Use plain product language and concrete examples. A compact text flow or rough wireframe is welcome when spatial or sequential behavior would otherwise be ambiguous.

The concept is ready for handoff when the problem, primary journey, MVP boundary, and consequential edge cases are agreed, and any unresolved item is explicitly recorded rather than guessed.

## Ground Technical Notes Late

Only after the product direction is stable, inspect the project when technical feasibility or handoff accuracy benefits from it. Prefer a focused graphify query, then inspect only the closest existing feature and relevant model or service. Distinguish confirmed repository facts from proposals.

Technical notes should identify likely touchpoints and meaningful risks. Avoid speculative file inventories, type names, or schema changes merely to make the handoff look complete.

## Handoff

When the user approves the concept and wants it captured, save:

```text
docs/features/YYYY-MM-DD-<kebab-case-feature-name>.md
```

Use the current local date and this structure, omitting sections that truly do not apply:

```markdown
# Feature: <Name>

## Decision summary
What we chose and why this direction won.

## Problem and outcome
Who has the problem, in what moment, and the outcome the feature should create.

## User experience
The entry point and end-to-end primary flow.

## Key states and edge cases
- Meaningful alternate, empty, error, permission, or destructive states

## MVP
- Included in the first useful release

## Non-goals
- Deliberately deferred or excluded

## Product decisions
- Consequential choices and their rationale

## Technical considerations
- Confirmed constraints, likely integration points, and data/privacy implications

## Success signals
- Observable evidence that the feature is useful

## Open questions
- Decisions intentionally left unresolved

## Where to start
The smallest validation or implementation step that reduces the most uncertainty.
```

End by stating what was saved and offering the next natural action, such as validating a risky assumption, creating an implementation plan, or beginning implementation. Do not take that next action without the user's direction.

## App Context

- The app uses Swift 6, SwiftUI, SwiftData, and MVVM.
- The repository pattern centers on `ITransactionRepository`.
- Feature folders live under `PersonalFinanceTraker/PersonalFinanceTraker/Features`.
- `TransactionModel` is the core transaction entity.
- Expenses are negative `Decimal`; income is positive.
- Categories use the `"emoji label"` string format.
- EUR is currently hardcoded.
- The app includes income, expense, budget, insight, import/export, and security workflows.
