# Feature: Health Score Redesign

## Problem
Three gaps in the current Health Score card: (1) the score number appears twice — inside the arc gauge and as "56 / 100" text beside it; (2) component rows give no context on why a score is low or how to improve it; (3) there is no trend indicator, so the user can't tell if their score is improving or regressing.

## Approach
Slim down the card to: arc gauge (number inside only) + score label + a trend delta pill (e.g. "+3 pts" / "−5 pts" vs last month). Tapping the card opens a new `HealthScoreDetailSheet` with the full breakdown: each component bar colored individually (green/amber/red based on its own score), a one-line actionable hint per component, and the trend delta prominently at the top. Trend is computed on the fly by re-running `FinancialHealthService.compute` on a window shifted back one month — no SwiftData schema changes required.

## Key decisions
- Remove "56 / 100" text from `HealthScoreCard` entirely — the arc gauge center already shows the number; the label ("Making progress") provides the qualitative read
- Trend delta: re-run `FinancialHealthService` with transactions filtered to the previous 6-month window (shifted by -1 month) and diff against current score; surface as a small pill (`+3 pts ↑` in green, `−5 pts ↓` in red, `= pts` in indigo)
- Per-component colors in the detail sheet: 0–12 → `.negative`, 13–18 → `.categoryAmber`, 19–25 → `.positive` (thresholds relative to each component's max of 25)
- Per-component hints: add a `hint: String` field to `ScoreComponent` in `FinancialHealthService` — each branch already knows why the score is low, so the hint can be set there (e.g. Stability = 0 → "Your monthly spending varies a lot — aim for consistency")
- "Tap card → detail sheet" is consistent with the Goals redesign pattern emerging on the Compass page
- The detail sheet is read-only — no editing, just context and trend

## Architecture notes

**Files to create:**
- `Features/Insights/Components/HealthScoreDetailSheet.swift` — trend delta header, component rows with individual colors and hint text, dismiss button

**Files to modify:**
- `Features/Insights/Components/HealthScoreCard.swift` — remove "56 / 100" text, add trend delta pill, add `.sheet` presentation on tap
- `Features/Insights/Components/HealthScoreSection.swift` — pass trend delta (computed in ViewModel) down to `HealthScoreCard`
- `Features/Insights/InsightsViewModel.swift` — add `healthScoreTrend: Int` computed by running `FinancialHealthService` on last month's window and diffing with current score
- `Utilities/FinancialHealthService.swift` — add `hint: String` to each `ScoreComponent` construction site

**SwiftData schema changes:** None

## Where to start
Add `hint: String` to `ScoreComponent` in `FinancialHealthService` — every score branch already has the context to write a good hint, and this unblocks building the detail sheet immediately after.
