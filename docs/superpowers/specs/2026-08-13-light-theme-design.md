# Light Theme + Appearance Picker — Design

**Date:** 2026-08-13
**Status:** Approved design, ready for implementation planning

## Goal

Add a light theme to PersonalFinanceTracker and let the user choose Auto / Light / Dark. "Auto" follows the system appearance. The light theme mirrors the existing dark brand language — same gradient blooms, same accent identity — rather than falling back to plain iOS system colors.

## Current state

The app is dark-only by construction:

- All 18 colorsets in `Assets.xcassets` define a **single appearance** (no light variant) — 16 semantic tokens plus `AccentColor` and `LaunchBackground`.
- `AppBackground` (`Utilities/DesignTokens.swift:62`) hardcodes base `#030712` plus three radial blooms.
- `PersonalFinanceTrakerApp.swift:19` paints `UIWindow` dark to suppress the launch-screen flash.
- ~22 call sites hardcode `Color.white.opacity(…)` / `Color.black.opacity(…)`.
- `AccentColor` is a reference to `systemBlueColor` and matches nothing in the app.

The token layer already exists, so most of the work is asset-catalog data rather than code.

---

## 1. Mechanism

A `ThemeMode` enum stored in `UserDefaults` via `@AppStorage`, applied at exactly one place in the view tree.

```swift
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  nil      // nil == follow system
        case .light: .light
        case .dark:  .dark
        }
    }
}
```

- **Storage:** `@AppStorage("app_theme_mode")`, default `.auto` for all installs (new and existing). This app is not on the App Store, so no migration flag is needed — an existing install may visibly flip to light on first launch, which is accepted.
- **Application:** `.preferredColorScheme(themeMode.colorScheme)` on `AuthenticationWrapper` in `PersonalFinanceTrakerApp.swift`. One modifier, one place.

> **Prerequisite — already done in `1145b09`.** Eight *production* views each pinned `.preferredColorScheme(.dark)` on their own body: `MainTabView:156` (the root tab view), `SplashView:39`, `InsightsView:109`, `ProfileView:193`, `EditFullNameView:13`, `PINSetupView:55`, `PINEntryView:67`, `PINConfirmationView:44`. Because a descendant's `preferredColorScheme` overrides an ancestor's, a single modifier on `AuthenticationWrapper` **would have had no effect** — the feature would have silently failed on every one of those screens. All eight are removed and replaced by one root declaration, currently hardcoded `.dark` to preserve today's behaviour; the picker work only has to swap that literal for `themeMode.colorScheme`.
>
> Seven further occurrences remain inside `#Preview` blocks. Those are dev-only and are intentionally left alone.

**No `AppSettings` change.** This follows the `ProfileCurrencySection` idiom, which already reads `@AppStorage` directly.

No view reads `@Environment(\.colorScheme)` except `AppBackground`. Everything else resolves through the asset catalog.

---

## 2. Contrast methodology

**All light values in this spec are verified against `#DDE1F1`, not against `bg0`.**

This matters. `AppBackground` composites radial blooms over the base color, and content sits on translucent `GlassCard` (`.glassEffect`). Neither is a flat `bg0`. `#DDE1F1` is the worst-case backdrop: the base `#E6EAF1` with the top-left indigo bloom and the centre indigo bloom overlapping at their new light-mode opacities.

Measuring against flat `bg0` overstates real contrast by roughly 0.6–0.9 ratio points, which is enough to push nominally-passing tokens below the bar in the middle of the screen.

**Bars applied by role:**

| Role | Bar | Rationale |
| --- | --- | --- |
| Text tokens | 4.5:1 | WCAG 1.4.3 (normal text) |
| Category fills | 3:1 | WCAG 1.4.11 (non-text contrast) |
| Overlay tokens | ~1.9:1 vs backdrop | matches the measured iOS separator on light |

---

## 3. Surface ramp

Hand-authored, hue 220° cool blue-gray. The dark ramp is bespoke (not on any Tailwind scale), so the light ramp is bespoke too.

Elevation direction is **preserved** from dark — more raised = lighter — rather than mirroring L\*. A pure L\* mirror would put gray cards on a near-white backdrop, inverting iOS convention.

| Token | Dark | Light | Light L\* |
| --- | --- | --- | --- |
| gradient base | `#030712` | **`#E6EAF1`** | 92.6 |
| `bg0` | `#060B18` | **`#EEF0F6`** | 94.8 |
| `bg1` | `#0D1526` | **`#F9FAFB`** | 98.2 |
| `bg2` | `#131D30` | **`#FFFFFF`** | 100.0 |

`LaunchBackground` takes the same **`#E6EAF1`** in light, staying coupled to the gradient base exactly as `#030712` is today.

The base was written out as a raw literal in **three** places — `DesignTokens.swift:66`, `PersonalFinanceTrakerApp.swift:19` and `AuthenticationWrapper.swift:31` (the last of which an earlier draft of this spec missed). As of `1145b09` all three read the `LaunchBackground` colorset via `Color.appBackgroundBase` / `UIColor(named:)`, so adding the light appearance to that one colorset is now sufficient.

---

## 4. Text and accent tokens

Verified ≥4.5:1 against the worst-case backdrop `#DDE1F1`.

| Token | Dark | Light | vs `#DDE1F1` | vs white |
| --- | --- | --- | --- | --- |
| `textPrimary` | `#F1F5F9` | **`#0F172A`** | 13.70:1 | 17.85:1 |
| `textMid` | `#94A3B8` | **`#475569`** | 5.81:1 | 7.58:1 |
| `textDim` | `#708096` | **`#576477`** | 4.61:1 | 6.01:1 |
| `accentIndigo` | `#6366F1` | **`#4F46E5`** | 4.82:1 | 6.29:1 |
| `positive` | `#22D3A0` | **`#0A6B4F`** | 4.99:1 | 6.50:1 |
| `negative` | `#F87171` | **`#991B1B`** | 6.38:1 | 8.31:1 |

`textDim` `#576477` is hue-matched to the custom `#708096`, not substituted with slate-500.

`accentIndigo` and `categoryIndigo` share **one value**, as they do in dark (both `#6366F1` today). `#4F46E5` clears the stricter 4.5:1 text bar, so the shared value is set by the text role.

`positive` `#0A6B4F` is chosen over the higher-contrast `#065F46` (5.90:1) deliberately: it keeps a 6.6 L\* gap to `negative` instead of 2.1, which matters more for colour-vision deficiency than the extra contrast headroom.

---

## 5. Category tokens

Category colours are **fills** (pie segments, icon chips, swatches), so the 3:1 non-text bar applies.

| Token | Dark | Light | vs `#DDE1F1` | L\* |
| --- | --- | --- | --- | --- |
| `categoryIndigo` | `#6366F1` | **`#4F46E5`** | 4.82:1 | 40.7 |
| `categoryPurple` | `#8B5CF6` | **`#7C3AED`** | 4.37:1 | 43.4 |
| `categoryPink` | `#EC4899` | **`#DB2777`** | 3.53:1 | 49.3 |
| `categoryAmber` | `#F59E0B` | **`#B45309`** | 3.85:1 | 46.9 |
| `categoryGreen` | `#22D3A0` | **`#0A6B4F`** | 4.99:1 | 39.8 |
| `categoryTeal` | `#14B8A6` | **`#0E7490`** | 4.11:1 | 45.1 |
| `categoryGray` | `#94A3B8` | **`#64748B`** | 3.65:1 | 48.3 |

`categoryTeal` moves from teal to **cyan-700** to open hue distance from `categoryGreen`; at teal-600 the two were 1.01:1 apart and read as one colour.

### Known limitation — colour alone is not sufficient

Seven categorical hues **cannot** be made CVD-distinguishable on a light background while all clearing the contrast bar. A search over staggered lightness ladders reached only 1.11:1 minimum pairwise separation under simulated deuteranopia, and only by driving colours to near-black (`#09382A`, `#610A35`) — worse on every other axis.

This is an over-determined constraint set, not a palette-tuning problem. The resolution is non-colour redundancy, which is the standard dataviz answer and is required by WCAG 1.4.1 regardless:

- **`CategoryPieChart` must label segments directly** (or carry a legend pairing swatch with name adjacently). Hue alone must never be the only encoding.
- **Amount signs — resolved.** An earlier draft called for verifying that `TransactionItemView.swift:52` renders a sign, treating its absence as likely. It was already partly there: expenses are stored as negative `Decimal`, so `.currency` rendered "-€12,34" for expenses and a bare "€12,34" for income. As of `561d563` the format carries `.sign(strategy: .always())`, so income reads "+€12,34" too — matching the convention `ImportResultView.formattedSignedAmount` already used. Direction of a transaction therefore never depends on colour.

  The measured deuteranopia separation between `positive` and `negative` is **1.05:1** in light (1.3 L\*) versus **1.18:1** in dark (5.3 L\*). Both are effectively identical, and light is measurably worse — but this describes a channel that is now redundant rather than load-bearing. `TransactionChart` is likewise safe (bars sit above/below the baseline, legend is text), as are the health-score bands (numeric score shown).

  This is a structural limit, not a tuning failure: on a light background both colours must be dark to clear 4.5:1, which compresses exactly the lightness range CVD users rely on. No hue choice escapes it — which is why the fix is a non-colour channel, not a better palette.

---

## 6. Overlay tokens

Two new colorsets replace the hardcoded white-alpha overlays.

| Token | Dark | Light | Light composited | vs backdrop |
| --- | --- | --- | --- | --- |
| `hairline` | `#FFFFFF` @ 10% | **`#0F172A` @ 28%** | `#AAAFB9` | 1.82:1 |
| `surfaceRaised` | `#FFFFFF` @ 7% | **`#0F172A` @ 10%** | `#D0D5DD` | 1.22:1 |

Tinted with slate-900 rather than pure black to keep the cool cast. Light alpha is **higher** than dark, not lower — low-alpha dark-on-light overlays are far less perceptible than the reverse. The 1.82:1 hairline is calibrated against the measured iOS separator on light (1.92:1).

Dark values are chosen to reproduce the current rendering, so dark mode is unchanged.

### Replacement map — 13 sites

**→ `hairline`** (dividers, strokes, grid lines)

| File | Line | Current |
| --- | --- | --- |
| `Insights/Components/HealthScoreDetailView.swift` | 73 | `Divider().overlay(Color.white.opacity(0.08))` |
| `Insights/Components/HealthScoreDetailView.swift` | 139 | `Divider().overlay(Color.white.opacity(0.08))` |
| `Insights/Components/SpendingTimelineChart.swift` | 84 | `AxisGridLine` 0.06 |
| `Insights/Components/ForecastCard.swift` | 108 | `Divider().overlay` 0.2 |
| `Insights/Components/ArcGaugeView.swift` | 11 | gauge track stroke 0.08 |

**→ `surfaceRaised`** (fills, tracks, row backgrounds)

| File | Line | Current |
| --- | --- | --- |
| `Insights/Components/HealthScoreDetailView.swift` | 190 | `.fill` 0.07 |
| `Insights/Components/HealthScoreCard.swift` | 36 | `.overlay` 0.1 |
| `Insights/Components/GoalCard.swift` | 46 | `.fill` 0.08 |
| `Insights/Components/ScoreComponentRow.swift` | 16 | `.fill` 0.07 |
| `CategorySettings/IconGridPicker.swift` | 27 | unselected chip 0.06 |
| `Security/PINSetupView.swift` | 148 | keypad background 0.08 |
| `Utilities/DesignTokens.swift` | 27 | `static let formRow = Color.white.opacity(0.06)` → `Color("surfaceRaised")` |

**Correction — `TransactionListView.swift:24` and `:27` stay white.** An earlier draft of this spec listed line 24 as a `hairline` site. That was wrong. Both strokes are the countdown ring inside `UndoDeleteBanner`, which renders within `ToastBanner`'s opaque black capsule — not against the app background. White is correct there in both themes, and converting them would make the ring invisible on the pill.

### Sites that stay hardcoded — 6

These are foreground-on-saturated-fill and are correct in both themes. Do not touch:

`Credit/Components/AddEditCreditCardSheet.swift:85` · `Security/PINSetupView.swift:122` · `Security/PINSetupView.swift:155` · `CategorySettings/ColorTokenPicker.swift:20` · `TransactionListView/Components/ImportResultView.swift:103` (always on `Color.accentColor`) · `Utilities/DesignTokens.swift:194,196` (`ToastBanner` — self-contained black pill with white text).

### Pre-existing light-mode defect that must be fixed — `ImportResultView`

`ImportResultView.swift:113` (`.tint(.white)` on the `ProgressView`) and `:127` (`.foregroundStyle(.white)`) sit inside a button whose background is:

```swift
.background(isImporting ? Color(.systemGray4) : Color.accentColor)
```

They are **not** always on a saturated fill. During the `isImporting` state the fill is `systemGray4`, and white on `systemGray4` measures:

| Theme | `systemGray4` | White foreground |
| --- | --- | --- |
| Dark | `#3A3A3C` | 11.35:1 — fine |
| Light | `#D1D1D6` | **1.52:1 — unreadable** |

The "Importing…" label and its spinner would be effectively invisible in light mode. The defect is latent today because the app is dark-only, so shipping light mode exposes it.

**Fix:** the white foreground must sit on a fill that holds ≥4.5:1 in both themes. Reference fix, verified: use `.textPrimary` for the importing state (11.73:1 on light `systemGray4`, and it inverts correctly in dark). Alternatively replace the `systemGray4` disabled fill with a token that keeps white legible in both themes — implementer's choice, but whichever is picked must be measured, not assumed.

---

## 7. AppBackground

The one legitimate `@Environment(\.colorScheme)` branch in the codebase — it is a gradient, not a token.

| Layer | Dark | Light |
| --- | --- | --- |
| base | `#030712` | **`#DCE0EE`** |
| indigo bloom, top-left | `#818CF8` @ 0.22 | **`#EEF0FF` @ 0.55** |
| teal bloom, bottom-right | `#22D3A0` @ 0.10 | **`#EAF7F3` @ 0.35** |
| indigo bloom, centre | `#6366F1` @ 0.10 | **`#EEF0FF` @ 0.35** |

**The two themes bloom in opposite directions, and that is the whole design.**

Dark adds light to a near-black base, so a strong bloom costs no contrast. Light originally used the same saturated hues at roughly a quarter opacity (0.05/0.03/0.03), because adding saturated indigo to a pale base *darkens* the backdrop toward the text and ate the contrast budget. The result was a gradient nobody could see: the bloom centres sit in the corners, so at that strength the falloff left it invisible across most of the screen, and light mode read as flat beside dark.

Light now blooms **lighter than its base**. Every bloomed region therefore has *more* contrast with text than the base does, not less — so the worst case for every token becomes the unbloomed base, a single fixed value under direct control. Bloom strength stops competing with contrast at all, which is why the light opacities can be an order of magnitude higher.

**Worst case is now simply `#DCE0EE`.** Verified: `textDim` 4.56:1, `accentIndigo` 4.77:1, `positive` 4.94:1, `textMid` 5.75:1, `negative` 6.31:1, `textPrimary` 13.55:1; every category fill ≥3.49:1 (tightest `categoryPink`). No token needed re-deriving. The earlier `#DDE1F1` / `#D7E1EF` composites no longer apply — they described a backdrop that darkened under blooms, which this one does not.

The darker base has a second effect: it widens the gap between the page and `bg0`/`bg1`, so the tinted Income/Expense chips on Activity — which sit directly on the page rather than inside a card as they do on Dashboard — separate from it visibly without changing their fill or their text colour.

Geometry, radii and `UnitPoint` centres are unchanged.

`GlassCard` needs no change — `.glassEffect` is system Liquid Glass and adapts on its own.

---

## 8. UI

New `Features/Profile/Components/ProfileAppearanceSection.swift`, matching the nine existing `Profile*Section` siblings:

- `Text("APPEARANCE")` caption header, `.font(.caption.weight(.semibold))`, `.foregroundStyle(.textDim)`, `.padding(.horizontal, 4)`
- Segmented `Picker` bound to `@AppStorage("app_theme_mode")`, three cases, `.tint(.accentIndigo)`

Inserted in `ProfileView.swift` as its own `Section { … }.appFormSectionBackground()` directly after the Currency section — both are display preferences.

---

## 9. AccentColor

`AccentColor` currently references `systemBlueColor`, so default-tinted system controls render blue while the app tints everything indigo. Repoint it to `#6366F1` (dark) / `#4F46E5` (light), matching `accentIndigo`.

Independent of this feature, but light mode makes the mismatch conspicuous.

---

## 10. Launch flash — accepted limitation

`UIWindow.appearance().backgroundColor` becomes `UIColor(named: "bg0")` so it resolves per appearance.

The **launch screen** resolves `LaunchBackground` against the *system* trait before any app code runs. A user who forces Dark on a light phone will see a light launch screen for a beat. This is not fixable via `preferredColorScheme` and is accepted.

If the window background itself mismatches during implementation, the fix is `overrideUserInterfaceStyle` on the window scene — verify before building it rather than adding it speculatively.

---

## 11. Testing

**`ThemeModeTests`** (Swift Testing, `@Test`/`#expect`):

- raw-value round-trip for all three cases
- `colorScheme` mapping: `.auto → nil`, `.light → .light`, `.dark → .dark`
- absent `UserDefaults` key defaults to `.auto`

Colour correctness is not unit-testable. Manual verification pass in light mode over the screens with changed tokens: Dashboard, Activity, Insights (health score, goals, forecast, timeline chart), Credit, Budgets, Profile, PIN setup/entry, category settings, CSV import result.

---

## 12. Out of scope

- **High-contrast appearance variants.** Asset catalogs support a `luminosity: high` slot for users with Increase Contrast enabled; neither the current dark tokens nor this light palette define one. Worth noting that several light tokens land at 4.4–4.6:1, so those users get no boost from a palette with no headroom. Deferred.
- **Per-screen UX/layout changes.** This spec covers the colour layer only.
- **Reducing the category palette below 7 hues.** Flagged by the audit as worth questioning; not part of this work.
- ~~**`PieChartDataService.swift:37-41`**~~ — **resolved in `561d563`.** It held a private 13-colour system palette assigned round-robin by index *after sorting by amount*, which meant a category's slice colour was a function of its spending rank and changed between periods. It also ignored `CategoryModel.colorToken` entirely — the colour the user picks in `ColorTokenPicker` had no effect on the chart. Slices now read the category's own token (falling back to `CategoryConstants.colorToken(forName:)` for unknown names), so §5's light values do apply to the pie chart and colour finally has a stable referent. Covered by three new tests in `PieChartDataServiceTests`, including a regression guard on rank-independence.
- **Threshold and destructive colours.** `CategoryDetailRow.progressBarColor` (`.red`/`.orange`/`.green`), swipe-action and validation `.red`, `AnomalyCalloutView`'s `.orange`. These are system semantic colours that already adapt per appearance and are HIG-idiomatic for their roles. Converting them to brand tokens would require inventing a warning token and would make them *worse*, not better. Left as-is deliberately.
