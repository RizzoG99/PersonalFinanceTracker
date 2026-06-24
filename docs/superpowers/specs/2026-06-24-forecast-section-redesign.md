# Forecast Section Redesign

**Date:** 2026-06-24  
**Status:** Approved

## Problem

The current `ForecastCard` is visually plain and inconsistent with the rest of the Compass tab. It renders aggregate numbers only (projected amount, 3-month avg, delta) with no visual representation of how spend is tracking across the month.

## Goal

Replace the plain card with a mini area/line chart showing cumulative daily spend for the current month (solid) plus a dashed projection to month-end, backed by a persisted sliding window cache so only new days are recomputed on each app open.

---

## Data Layer

### `DailyForecastCache` (new SwiftData model)

```swift
@Model
final class DailyForecastCache {
    var monthKey: String       // "2026-06" — used for month-boundary invalidation
    var computedUpToDay: Int   // last calendar day with actual data
    var days: [Int]            // [1, 2, 3, ...]
    var amounts: [Double]      // cumulative spend per day, base currency (Double, not Decimal)
}
```

`Decimal` is not SwiftData-native; `Double` is sufficient for chart display. No migration needed (app is not on the App Store).

### `DailyPoint` (new value type in `CompassDataModels.swift`)

```swift
struct DailyPoint: Identifiable {
    let id = UUID()
    let day: Int
    let cumulative: Decimal
}
```

### `SpendingForecast` (extended)

Add `dailyActuals: [DailyPoint]` to the existing struct. All other fields (`projectedAmount`, `dailyPace`, `lastThreeMonthAvg`, `daysLeft`) remain unchanged.

### `ITransactionRepository` (two new methods)

```swift
func fetchForecastCache() throws -> DailyForecastCache?
func saveForecastCache(_ cache: DailyForecastCache) throws
```

---

## Service Layer

### `SpendingForecastService.compute()` (updated signature)

```swift
func compute(
    expenseTransactions: [TransactionModel],
    cache: DailyForecastCache?
) -> (forecast: SpendingForecast, updatedCache: DailyForecastCache)
```

**Sliding window algorithm:**

1. Compute `currentMonthKey` (e.g. `"2026-06"`).
2. **Cache miss / month boundary:** if `cache == nil` or `cache.monthKey != currentMonthKey` → full recompute of all days 1..`daysElapsed`, build complete `days` + `amounts` arrays.
3. **Cache hit:** load `cache.amounts.last` as the starting cumulative. Fetch only transactions from day `cache.computedUpToDay + 1` through today. Accumulate from the last cached value, append new `(day, cumulative)` pairs.
4. Convert `(days, amounts)` arrays into `[DailyPoint]` for the forecast model — `amounts: [Double]` → `cumulative: Decimal(string: String(amount))` to avoid floating-point drift on display.
5. Return `(SpendingForecast, DailyForecastCache)`.

The service remains a pure, stateless struct. It does not touch SwiftData directly.

### `CompassViewModel.computeForecast()` (updated)

```swift
private func computeForecast() {
    let cache = try? repo.fetchForecastCache()
    let (fc, updatedCache) = forecastService.compute(
        expenseTransactions: expenseTransactions,
        cache: cache
    )
    try? repo.saveForecastCache(updatedCache)
    forecast = fc
}
```

---

## View Layer

### `ForecastCard` (redesigned)

Layout (top to bottom inside `GlassCard`):

1. **Header row** — "At this pace" label + "N days left" badge (unchanged).
2. **Swift Charts area** — the visual centrepiece:
   - `AreaMark` + `LineMark` for `dailyActuals` (days 1..today), tinted with `trendColor` (green = under pace, red = over pace).
   - Dashed `LineMark` from today's last actual point to `(daysInMonth, projectedAmount)` — a single two-point segment, not per-day extrapolation.
   - Horizontal `RuleMark` at `lastThreeMonthAvg` — subtle dashed line, labeled "avg", so the user sees their historical baseline at a glance.
   - X-axis: day numbers, minimal labels (first day, today, last day).
   - Y-axis: hidden labels, grid lines only.
3. **Summary row** — projected amount (bold), delta vs avg (`+€X` / `-€X`), 3-month avg label. Same information as today, moved below the chart.

`ForecastSection` header ("Forecast / Month-end projection") and `InsightsEmptyCard` empty state are unchanged.

### Empty / insufficient data

`ForecastSection` shows `InsightsEmptyCard` when `forecast == nil` or `lastThreeMonthAvg == 0`. If `dailyActuals` is non-empty but fewer than 3 days, the chart still renders — partial data is valid.

---

## Out of Scope

- Budget target line (no budget concept at month level yet).
- Category breakdown within the chart.
- Tappable chart points / drill-down.
