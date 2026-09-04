# Android visual-parity baseline

This document translates the current iOS visual system into native Android rules. It is a shared
baseline for Android parity work; it does not require reproducing iOS controls pixel for pixel.

| iOS source | Android implementation | Intent |
| --- | --- | --- |
| `AppBackground` | `AppBackground` Compose component | Calm warm background with subtle indigo and teal blooms in both appearances. |
| `accentIndigo`, semantic ink and surface tokens | `PersonalFinanceTheme` Material 3 scheme and `FinancePalette` | Keep primary actions, financial semantics, surfaces, and text hierarchy consistent. |
| `GlassCard` | `FinanceCard` | Group balance, summaries, and transactions without heavy elevation. |
| Dashboard balance card | Home financial overview | Put balance first, then the current pay-cycle income and expenses. |
| iOS tab shell | Compose `NavigationBar` | Preserve Home, Activity, and Insights information architecture using Android navigation behavior. |

## Guardrails

- Feature screens use theme roles and shared components; they do not define local colors.
- Positive and negative money values use explicit signs as well as semantic color.
- Native Material controls remain native. The app mirrors iOS hierarchy and character, not iOS interaction mechanics.
- Each visual parity feature must be reviewed in light/dark appearance, compact/wide layouts, and with large localized text before it is marked matched.

## Screenshot references

Use the current iPhone captures as the parity reference, especially
`docs/screenshots/iphone/{light,dark}/01-dashboard.png` and
`docs/screenshots/iphone/{light,dark}/02-activity.png`. They describe information hierarchy,
colour relationships, and states; Android retains Material navigation, sheets, and back behaviour.

## Verification record

- 2026-09-04: Home and Activity empty states inspected on a Pixel 7 emulator in dark and light
  appearance. The app shell, system bars, readable foreground colour, dashboard greeting/balance
  hierarchy, Activity search surface, and empty-state action were checked against the current
  iPhone captures.
- Still required before visual parity sign-off: populated transaction states, light appearance,
  compact/wide and large-font layouts, TalkBack order, keyboard/sheet behaviour, and destructive
  flows. Track these against Android issue #92; keep issue #93 open until they are complete.
