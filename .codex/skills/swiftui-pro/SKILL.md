---
name: swiftui-pro
description: Reviews, writes, and improves SwiftUI code for modern APIs, maintainability, accessibility, data flow, navigation, and performance. Use when Codex is reading, changing, or reviewing Swift/SwiftUI code in this iOS app.
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

1. Read `AGENTS.md` and the relevant source/test files.
2. Load only the reference files needed for the task:
   - `references/api.md` for deprecated or modernized APIs.
   - `references/views.md` for view composition, modifiers, and animation.
   - `references/data.md` for state, SwiftData, bindings, and data flow.
   - `references/navigation.md` for navigation, sheets, alerts, and dialogs.
   - `references/design.md` for HIG-oriented UI decisions.
   - `references/accessibility.md` for Dynamic Type, VoiceOver, Reduce Motion, and touch targets.
   - `references/performance.md` for render and data performance.
   - `references/swift.md` for Swift and concurrency.
   - `references/hygiene.md` for maintainability and compile hygiene.
3. Make the smallest scoped code change that satisfies the request.
4. Add or update Swift Testing coverage when behavior changes.
5. Prefer Xcode MCP build/test tools when available; do not run shell `xcodebuild` without explicit user approval.

## Review Output

When asked for a review, lead with findings ordered by severity. Include file and line references, the impact, and a concrete fix. Keep summaries secondary.
