---
name: swiftui-pro
description: Designs, reviews, writes, and improves SwiftUI code for modern APIs, app-theme consistency, Apple platform conventions, maintainability, accessibility, data flow, navigation, and performance. Use when a coding agent is planning, reading, changing, or reviewing Swift/SwiftUI UI in this iOS app.
---

# SwiftUI Pro

Review and modify SwiftUI code for correctness, modern API usage, maintainability, performance, and project conventions. Report only genuine problems.

## Project Defaults

- Target iOS 26 and Swift 6 unless the project file says otherwise.
- Prefer SwiftUI and SwiftData; avoid UIKit and third-party frameworks unless explicitly requested.
- Use MVVM and feature-based folders under `PersonalFinanceTraker/PersonalFinanceTraker/Features`.
- Split meaningful types into separate files when that matches the surrounding feature.
- Preserve the app typo: `PersonalFinanceTraker`.
- Expenses are negative `Decimal`; income is positive.
- EUR formatting is currently the app default.

## Workflow

1. Read the active agent's project instructions (`AGENTS.md` for Codex, `CLAUDE.md` for Claude Code) and the relevant source/test files. Other agents should use `AGENTS.md` as the project-default entry point.
2. For any user-facing UI, read `references/design.md` and inspect the two closest existing screens or components before proposing or implementing the design.
3. Load only the other reference files needed for the task:
   - `references/api.md` for deprecated or modernized APIs.
   - `references/views.md` for view composition, modifiers, and animation.
   - `references/data.md` for state, SwiftData, bindings, and data flow.
   - `references/navigation.md` for navigation, sheets, alerts, and dialogs.
   - `references/design.md` for HIG-oriented UI decisions.
   - `references/ui-patterns.md` when the feature includes empty/loading/error states, feedback, search/filter/sort, toolbars, or financial-value presentation.
   - `references/accessibility.md` for Dynamic Type, VoiceOver, Reduce Motion, and touch targets.
   - `references/performance.md` for render and data performance.
   - `references/swift.md` for Swift and concurrency.
   - `references/hygiene.md` for maintainability and compile hygiene.
4. Make the smallest scoped code change that satisfies the request.
5. Add or update Swift Testing coverage when behavior changes.
6. For UI changes, complete the quality gate in `references/design.md`; report any check that could not be performed.
7. Prefer the repository's `scripts/xcb` commands for builds and tests, following the active agent's project instructions.

## Review Output

When asked for a review, lead with findings ordered by severity. Include file and line references, the impact, and a concrete fix. Keep summaries secondary.
