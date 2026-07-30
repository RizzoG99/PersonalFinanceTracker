# UX/UI Audit — Personal Finance Tracker — Insight/Anomaly copy components — 2026-07-30

## Screens audited
- Code-only review, no screenshots: `Utilities/SpendingInsightService.swift`, `Utilities/FinancialHealthService.swift`, `Features/Dashboard/Components/AnomalyCalloutView.swift`, `Features/Dashboard/DashboardViewModel.swift` (message-construction site, `:147`)
- Scope: these were surfaced while localizing the app into Italian (see plan `check-in-the-project-magical-boot.md`) — the components that assemble finished English sentences in the model/service layer instead of returning structured data.

## Per-screen findings

### AnomalyCalloutView
- **Severity: High — Problem:** `message: String` (`AnomalyCalloutView.swift:9`) receives a fully-baked sentence from `DashboardViewModel.swift:147` (`"Unusually high spending in \(spike.period): \(amount.formatted(...))"`). The icon, message `Text`, and dismiss `Button` are three separate elements with no `accessibilityElement(children: .combine)`. **Why it hurts UX:** WCAG / screen-reader friendliness — VoiceOver announces the warning triangle, the sentence, and "Dismiss" as three disconnected stops instead of one coherent warning. **Recommendation:** group into a single accessibility element with the icon's meaning folded into the label/trait, not a separate focus stop.
- **Severity: Medium — Problem:** Severity (this is a *warning*) is communicated only via `.orange` fill/icon color (`AnomalyCalloutView.swift:15,30`) plus a triangle icon; there's no textual severity marker beyond the sentence content itself. **Why it hurts UX:** WCAG 1.4.1, don't rely on color alone — partially mitigated by the ⚠️ icon, but a low-vision user distinguishing "info" vs "warning" callouts app-wide has only color as the differentiator if more callout types are added later. **Recommendation:** if more callout severities are ever added, give each an explicit accessibility trait/prefix, not just a tint.
- **Severity: Medium (i18n root cause) — Problem:** Because `message` is a pre-formatted `String` built in the view model, it can't be a `LocalizedStringKey`/format-string — the view has no way to localize it without the view model doing the localizing itself, which is backwards (business logic owning presentation). **Recommendation:** `DashboardViewModel` should expose `(period: String, amount: Decimal)`; the view builds and localizes the sentence, formatting the amount at render time.

### SpendingInsightService (HeroInsight / HabitObservation)
- **Severity: Medium — Problem:** `HeroInsight.emoji` (`"🎉"`, `"⚡"`, `"📊"`, `"✨"`) carries the emotional tone of the insight but has no text equivalent — VoiceOver reads literal emoji names ("party popper," "high voltage") which convey nothing about spending trends. **Why it hurts UX:** Nielsen's *match between system and the real world* — the visual/tone signal is invisible to screen-reader users, who already have `trendDirection` (`.up`/`.down`/`.flat`) available as a clean semantic alternative that isn't being surfaced accessibly. **Recommendation:** derive an `accessibilityLabel` from `trendDirection` (e.g. "spending decreased") rather than let VoiceOver read the emoji glyph name.
- **Severity: Medium — Problem:** Ratio-based observations (`"Weekend spending is 1.3× higher"`, `SpendingInsightService.swift:121`) state a fact with no valuation — nothing tells the user whether this is good, bad, or simply notable. **Why it hurts UX:** Nielsen's *help users recognize, diagnose, and recover* / lack of guidance — a bare ratio requires the user to do their own interpretation on every glance. **Recommendation:** consider a lightweight valence cue (color/icon) distinguishing "you might want to look at this" vs. purely neutral pattern info, consistent with how budget cards already use amber/red tiering.
- **Severity: Low — Problem:** The 1.3× threshold (`:117`, `:126`) has a ratio floor but no absolute-amount floor — on a week with very low total spend, a small absolute difference can produce a large, attention-grabbing ratio ("2.1× higher") that's numerically true but practically noise. **Why it hurts UX:** repeated low-value insights erode trust in the insights feature as a whole (the "boy who cried wolf" effect on notification-like UI). **Recommendation:** require a minimum absolute delta (e.g. weekend/weekday average difference > some €X) in addition to the ratio before surfacing the observation.
- **Severity: Low (i18n root cause) — Problem:** Count-dependent titles (`"\(streak)-week streak"`, `"\(subCount) subscription charges this month"`, the `"category"/"categories"` ternary in the related `FinancialHealthService.adherenceTip`) are hand-rolled singular/plural ternaries baked into English sentences. **Why it hurts UX:** Italian pluralization rules don't map onto English ternary logic (different plural boundaries, different word endings) — a straight string substitution would produce grammatically wrong Italian. **Recommendation:** replace the ternaries with String Catalog plural variations (`.stringsdict`-style `one`/`other` categories), which each locale's translator fills in independently.

### FinancialHealthService explanation/tip helpers
- **Severity: Low (i18n root cause) — Problem:** `savingsExplanation`, `stabilityExplanation`, `adherenceExplanation`, `subscriptionExplanation`, and their `*Tip` counterparts (`FinancialHealthService.swift:139-183`) build plain `String` sentences with embedded numbers, some concatenating a currency literal directly (`"Save €\(rounded) more per month..."`, `:152`) rather than using the app's existing locale-aware `formattedEUR()` helper. **Why it hurts UX / correctness:** hardcoding `€` breaks for any future non-EUR path and bypasses the app's own currency-formatting convention used everywhere else (`StatCard`, `BalanceCardView`). **Recommendation:** use the existing `formattedEUR()`/currency formatter instead of string-interpolating the euro sign directly, and wrap each sentence in `String(localized:)` once extracted.

## Cross-screen consistency issues
- All four files share the same anti-pattern: **services/view models return finished English sentences instead of structured data**, and views only ever call `Text(theString)`. This is the single root cause behind both the localization gap and the accessibility grouping gaps found here — fixing the data shape (service returns `(value, unit, direction)`-style tuples; view renders + localizes) resolves both problems at once rather than needing two separate passes.

## Executive Summary

**Top UX problems**
1. Presentation logic (finished sentences) lives in services/view models, not views — blocks both localization and per-fragment view control (High, architectural)
2. `AnomalyCalloutView` has no combined accessibility element — 3 disjoint VoiceOver stops (High)
3. Emoji-as-tone-signal has no accessible text equivalent (Medium)
4. Ratio-based insights state facts with no valence/guidance (Medium)
5. No absolute-amount floor on ratio-triggered insights — risk of noisy, trivial alerts (Low)

**Top UI problems**
1. Warning severity communicated by color/icon only, no text marker (Medium)
2. Hardcoded `€` literal bypasses the app's own currency formatter (Low)

**Biggest accessibility issues**
- No `accessibilityElement(children: .combine)` on `AnomalyCalloutView`.
- Emoji tone signals (`HeroInsight.emoji`) unreadable by VoiceOver.

**Biggest consistency issues**
- Four different files independently hand-roll singular/plural English sentences instead of using one shared plural-aware formatting convention.

## Quick Wins
*(implementable in under one day)*
- Add `.accessibilityElement(children: .combine)` to `AnomalyCalloutView`.
- Replace the hardcoded `"€\(rounded)"` in `FinancialHealthService.savingsTip` with the existing `formattedEUR()` helper.
- Derive `HeroInsight`'s accessibility label from `trendDirection` instead of the raw emoji.

## High Impact Improvements
*(moderate effort, big UX payoff)*
- Refactor `AnomalyCalloutView`/`DashboardViewModel` and `SpendingInsightService`/`FinancialHealthService` to return structured data (period/amount/count/direction) instead of pre-built sentences; views localize and render. Solves localization and the accessibility grouping gap together (tracked as Phase 2 of the localization plan).
- Convert count-dependent sentences to String Catalog plural variations instead of hand-rolled ternaries.

## Long-term Improvements
*(architectural/design-system changes)*
- Add an absolute-amount floor alongside the existing ratio threshold for ratio-triggered insights, to reduce noise as more transaction history accumulates.
- Consider a documented valence convention (color/icon tiering, similar to budget-card amber/red) for insight cards so users can tell "worth a look" from "just an observation" at a glance.

## UX Score (1–10)
- **Visual Design: 7/10** — not screenshot-verified; code shows consistent SF Symbol + color usage matching the rest of the app.
- **Usability: 6/10** — insights are informative but several state raw facts (ratios, streak counts) without guidance on what to do next.
- **Accessibility: 4/10** — no combined VoiceOver element on the anomaly callout, emoji tone signals unreadable by screen readers.
- **Information Architecture: 7/10** — logically grouped (hero → category trends → habit observations), no navigation issues found.
- **Navigation: n/a** — not applicable to this code-only scope.
- **Consistency: 5/10** — presentation-logic-in-service-layer pattern repeats across 3 separate files with no shared convention.
- **Learnability: 7/10** — insight cards are self-explanatory in isolation.
- **Overall Experience: 6/10** — functionally solid insights engine let down by an architectural pattern (baked-in sentences) that blocks both localization and clean accessibility grouping.

## Redesign Suggestions

### AnomalyCalloutView — structured data + combined accessibility
```
Before:
DashboardViewModel → message: String → AnomalyCalloutView(message:)

After:
DashboardViewModel → (period: String, amount: Decimal) → AnomalyCalloutView
  Text("Unusually high spending in \(period): \(amount, format: .currency(code: "EUR"))")
    // localized format key: "Unusually high spending in %@: %@"
  .accessibilityElement(children: .combine)
  .accessibilityLabel("Warning: unusually high spending in \(period), \(amount)")
```

### Habit observation — plural-safe count copy
```
Before: "\(subCount) subscription charges this month"   // English-only plural logic
After:  String(localized: "^[\(subCount) subscription charge](inflect: true) this month")
        // or catalog plural variation keyed on subCount — `it` gets its own one/other forms
```
