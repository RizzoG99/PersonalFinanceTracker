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
