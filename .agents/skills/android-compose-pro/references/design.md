# Android visual design and parity

Use this reference for every new or materially changed Compose screen. The goal is Android-native
interaction with recognisable iOS product hierarchy, not a pixel-for-pixel iOS recreation.

## Required preflight

1. Read `docs/android/visual-parity.md`, `ui/theme/PersonalFinanceTheme.kt`, and the two closest
   Android screens/components.
2. When visual parity is part of the request, inspect the matching iOS feature and its shared
   primitives before deciding the Android structure.
3. State the primary task, primary action, navigation or sheet behavior, and all reachable UI
   states before coding.
4. Reuse `AppBackground`, `FinanceCard`, semantic Material color roles, and shared formatters
   before creating a new visual primitive.

## Visual language

- Use `AppBackground` for top-level destinations and transparent screen scaffolds so its indigo
  and teal blooms remain visible.
- Use `FinanceCard` for grouped balance, summary, and transaction content. Do not stack decorative
  cards, gradients, shadows, or outlines without an information-hierarchy reason.
- Use `MaterialTheme.colorScheme` and `LocalFinancePalette`; feature code must not introduce
  literal colors for reusable semantics.
- `primary` is for actions and selection. `positive` and `negative` communicate financial
  direction, always reinforced with a sign, label, icon, or position.
- Prefer Material 3 controls and navigation. Android should retain Android back behavior, sheets,
  menus, and touch feedback even where iOS uses a different control.
- Use Compose text styles and flexible layout. Do not give text-bearing elements fixed dimensions
  that break with Italian, font scaling, split-screen, or tablets.

## Quality gate

Before calling Android UI complete, verify or explicitly leave open:

- consistency with two Android peers and the iOS parity reference when relevant;
- populated, empty, loading, no-results, error, disabled, success, and destructive states that
  the screen can actually reach;
- compact phone and wide/tablet layouts, including landscape when applicable;
- light and dark appearance;
- large font scale, TalkBack reading order and labels, contrast, and 48 dp interactive targets;
- long localized copy, large positive and negative monetary values, scrolling, keyboard, sheet,
  navigation, and system-bar behavior;
- a representative build/test run and emulator or device inspection when the UI changed.

A clean build, static analysis, or screenshot in one appearance is not sufficient visual sign-off.
