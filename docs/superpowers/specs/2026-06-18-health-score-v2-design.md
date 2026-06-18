# Health Score V2 — Design Spec

**Date:** 2026-06-18  
**Status:** Approved

---

## Overview

Improve the existing Health Score feature across four axes:
1. **Score history** — persist and display score trend over time
2. **Actionable tips** — each component explains why the score is what it is and what to fix
3. **Plain-language explanations** — tap through to a detail view with full breakdown
4. **Component flexibility** — let users opt out of the subscription metric

---

## Data Layer

### `HealthScoreSnapshot` (new SwiftData model)

```swift
@Model class HealthScoreSnapshot {
    var timestamp: Date
    var score: Int
    var savingsScore: Int
    var stabilityScore: Int
    var adherenceScore: Int
    var subscriptionScore: Int
}
```

- Saved once per app session on `InsightsViewModel` load
- Only saved if no snapshot exists for today (guard against duplicates)
- Fetched with a `limit: 6` cap for the trend chart

### Repository changes

Two new methods added to `ITransactionRepository` and `TransactionRepository`:

```swift
func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws
func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot]
```

### Subscription opt-out

```swift
@AppStorage("healthScore.ignoreSubscriptions") var ignoreSubscriptions: Bool = false
```

When `true`, `FinancialHealthService` redistributes the subscription component's 25 pts proportionally across the other 3 components (each scales to ~33 pts max), keeping the total at 100.

---

## Service Layer

### `ScoreComponent` — extended

```swift
struct ScoreComponent: Identifiable {
    let id: UUID
    let name: String
    let score: Int
    let max: Int
    let explanation: String   // plain-language description of current result
    let tip: String?          // nil when score == max; concrete improvement action otherwise
}
```

### `FinancialHealthService.compute()` — updated signature

```swift
func compute(
    transactions: [TransactionModel],
    expenseTransactions: [TransactionModel],
    budgetedCategories: [CategoryModel],
    ignoreSubscriptions: Bool
) -> HealthScore
```

### Per-component tip and explanation logic

Tips are only generated when `score < max`. All strings are number-driven — no generic advice.

| Component | Explanation example | Tip example |
|---|---|---|
| Savings rate | "You saved 12% of income over 6 months." | "Save €80 more/month to reach the 20% target." |
| Stability | "Your monthly spending varies by 38%." | "Under 25% variation earns full points." |
| Budget | "2 of 4 budgeted categories are over limit." | "Bring Food and Transport within budget." |
| Subscriptions | "Subscriptions are 11% of expenses." | "Keep them under 15% to score higher." |

Tip and explanation generation lives in `FinancialHealthService` alongside the math, keeping numbers and copy in sync.

---

## UI Layer

### `HealthScoreCard` — changes

- **Sparkline trend line** inserted above the arc gauge: 6-point line chart from recent snapshots, colored green if trending up, red if down, neutral if flat
- **Card is tappable** — presents `HealthScoreDetailView` as a `.sheet`

### `HealthScoreDetailView` (new)

Presented as a sheet from `HealthScoreSection`. Three sections in a `ScrollView`:

**1. History Chart**
- Swift Charts `LineChart` plotting last 6 `HealthScoreSnapshot` scores
- X-axis: month labels; Y-axis: 0–100
- Current score highlighted with a point annotation

**2. Component Breakdown**
- Each `ScoreComponent` rendered as an expanded row:
  - Name + score bar (same visual style as today)
  - `explanation` string in caption style below the bar
  - `tip` shown in an amber callout if `score < max`
- All info inline — no further tap interaction needed

**3. Subscription Toggle**
- At the bottom of the sheet
- Label: *"Exclude subscriptions from score"*
- Writes to `@AppStorage("healthScore.ignoreSubscriptions")`
- Triggers score recompute in `InsightsViewModel`

---

## Data Flow

```
InsightsViewModel.load()
  → FinancialHealthService.compute(..., ignoreSubscriptions)
  → HealthScore (with tips + explanations)
  → if no snapshot today → repository.saveSnapshot()
  → repository.fetchSnapshots(limit: 6) → [HealthScoreSnapshot]

HealthScoreSection
  → HealthScoreCard (score + sparkline from snapshots)
  → .sheet → HealthScoreDetailView (history chart + components + toggle)
```

---

## Files to Create

- `PersonalFinanceTraker/Models/HealthScoreSnapshot.swift` — SwiftData model
- `PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift` — detail sheet

## Files to Modify

- `PersonalFinanceTraker/Models/CompassDataModels.swift` — extend `ScoreComponent`
- `PersonalFinanceTraker/Models/TransactionRepository.swift` — add snapshot methods
- `PersonalFinanceTraker/Utilities/FinancialHealthService.swift` — tips, explanations, opt-out param
- `PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift` — sparkline + tap
- `PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift` — sheet presentation
- `PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift` — snapshot save/fetch, opt-out binding
- `PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift` — register `HealthScoreSnapshot` in ModelContainer schema

---

## Out of Scope

- "What-if" simulator (deferred to V3)
- Configurable component weights
- Push notifications for score changes
