---
name: android-compose-pro
description: Designs, reviews, writes, and improves Kotlin and Jetpack Compose UI for Personal Finance Tracker's Android app. Use for Android interface implementation, navigation, visual parity, accessibility, state handling, and Compose UI review; do not use for non-UI Android infrastructure.
---

# Android Compose Pro

Build Android interfaces that feel native to Android while preserving the information hierarchy,
financial semantics, and visual character of the iOS app.

## Project defaults

- Android code lives in `Android/`; it uses Kotlin, Jetpack Compose, Material 3, Room, DataStore,
  MVVM, and repository boundaries.
- Minimum SDK is 26. Use `BigDecimal` for money; expenses are negative in storage and income is
  positive. Convert to display values only at the UI boundary.
- User-facing strings belong in `res/values/strings.xml`, with natural Italian equivalents in
  `res/values-it/strings.xml`.
- `PersonalFinanceTheme`, `AppBackground`, `FinanceCard`, and
  `docs/android/visual-parity.md` are the Android visual source of truth. The iOS implementation
  remains the product reference when Android parity is requested.

## Workflow

1. Read `AGENTS.md` and the relevant Android source and tests. Inspect the two closest Android
   screens or components before proposing a new UI.
2. For a user-facing screen, read [design.md](references/design.md). For data or state work, read
   [architecture.md](references/architecture.md). Load only the other references relevant to the
   task.
3. Define the screen's primary task, primary action, navigation/presentation, and reachable
   loading, populated, empty, no-results, error, disabled, success, or destructive states.
4. Make the smallest scoped change. Reuse theme roles and shared components before adding a new
   token or primitive.
5. Add or update focused tests when behavior changes. Use `./gradlew :app:assembleDebug` and
   `./gradlew :app:testDebugUnitTest`; deploy to an emulator/device when visual verification is
   relevant.
6. Complete the applicable quality gate in [design.md](references/design.md). Report any visual,
   accessibility, or device check that could not be run instead of claiming it passed.

## Reference routing

- [design.md](references/design.md): visual parity, theme roles, layout, and the UI quality gate.
- [ui-patterns.md](references/ui-patterns.md): financial values, app states, search/filters,
  toolbars, feedback, sheets, and destructive actions.
- [accessibility.md](references/accessibility.md): TalkBack, font scaling, contrast, and input.
- [architecture.md](references/architecture.md): Compose state, ViewModels, Flow, Room, DataStore,
  navigation, and tests.

## Review output

For a review, lead with genuine findings ordered by severity. Include the Android file and line,
the user impact, and a concrete correction. Keep summaries secondary.
