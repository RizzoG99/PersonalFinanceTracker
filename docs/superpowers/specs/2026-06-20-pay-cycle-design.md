# Pay Cycle Start Day — Full Feature Spec

**Date:** 2026-06-20
**Status:** Approved for implementation

---

## Problem

Calendar months misalign with income cycles. If a salary arrives on the 10th, a Jan 1–Jan 31 window captures the December salary (arrived Dec 10) but misses the January one (arrives Jan 10). Health score, budget adherence, and KPI calculations all look wrong even though nothing is wrong financially.

A user-defined financial month start (e.g. the 10th) makes every period window Dec 10–Jan 9, Jan 10–Feb 9, etc. — one pay cycle per "month", always.

---

## Scope

The pay cycle start day affects:

- **Health score** — savings rate, spending stability, budget adherence (already partially wired)
- **Dashboard KPIs** — "this month" income / expenses
- **Activity Month view** — chart data window and filter
- **Category Breakdown Month view** — pie/bar chart filter

The setting is a single integer (1–28), persisted in UserDefaults under key `"payCycleStartDay"`.

---

## What Already Exists

These were built in recent commits and are not changed by this feature, only wired up correctly:

- `PayCycleService` — `financialMonthStart(for:startDay:)`, `financialMonths(count:before:startDay:)`, `currentFinancialMonth(startDay:)`
- `FinancialHealthService.compute(payCycleStartDay:)` — already uses `PayCycleService`
- `ProfilePayCycleSection` — Stepper UI (1–28) with description text
- `HealthScoreDetailView` — already shows financial period dates

The main gap: `ProfileViewModel` and `CompassViewModel` each hold an independent copy of `payCycleStartDay` read from UserDefaults at init. No sync exists between them or with `DashboardViewModel` / `ChartDataService` / `PieChartDataService`, which still use hardcoded calendar months.

---

## Architecture: Approach A — AppSettings + PayCycleAware Modifier

### Single Source of Truth: `AppSettings`

```
Utilities/AppSettings.swift
  @Observable final class AppSettings
    var payCycleStartDay: Int   // didSet → UserDefaults.standard.set(..., forKey: "payCycleStartDay")
    init()                      // reads UserDefaults, defaults to 1 when key absent
```

- Created once in `MainTabView` as `@State private var appSettings = AppSettings()`
- Injected app-wide via `.environment(appSettings)`
- Replaces the independent copies in `ProfileViewModel` and `CompassViewModel`

**Removed:**
- `ProfileViewModel.payCycleStartDay` (property + UserDefaults read/write)
- `CompassViewModel.payCycleStartDay` (property + UserDefaults read/write + `didSet` trigger)

### Sync: `PayCycleAwareModifier`

```
Utilities/PayCycleAwareModifier.swift
  struct PayCycleAware: ViewModifier
    @Environment(AppSettings.self) private var appSettings
    let load: () -> Void

    func body(content:) -> some View
      content
        .onAppear { load() }
        .onChange(of: appSettings.payCycleStartDay) { _, _ in load() }

extension View
  func payCycleAware(load: @escaping () -> Void) -> some View
```

Applied at four call sites:

```swift
DashboardView()         .payCycleAware { dashboardViewModel.load() }
ActivityView(...)       .payCycleAware { transactionListViewModel.load() }
CategoryBreakdownView() .payCycleAware { categoryBreakdownViewModel.load() }
CompassView(...)        .payCycleAware { compassViewModel.load() }
```

When the user moves the Stepper in Profile → `appSettings.payCycleStartDay` changes → SwiftUI fires `.onChange` in all four views → each VM recomputes with the new window immediately. No app restart required.

---

## Changes by File

### New Files

| File | Purpose |
|------|---------|
| `Utilities/AppSettings.swift` | `@Observable` single source of truth for `payCycleStartDay` |
| `Utilities/PayCycleAwareModifier.swift` | `ViewModifier` that triggers `load()` on appear and on payCycleStartDay change |

### Modified: `MainTabView`

- Add `@State private var appSettings = AppSettings()`
- Add `.environment(appSettings)` to the `TabView`
- Pass `appSettings` to each VM at init:
  ```swift
  _dashboardViewModel = State(wrappedValue: DashboardViewModel(repo: ..., appSettings: appSettings))
  // CompassViewModel is created inside CompassView — pass appSettings via environment or init
  ```
- Apply `.payCycleAware { ... }` to each tab's root view

### Modified: `ProfileViewModel`

- Remove `payCycleStartDay` property (both the stored property and UserDefaults round-trip)

### Modified: `ProfilePayCycleSection`

- Remove `@Binding var payCycleStartDay: Int`
- Add `@Environment(AppSettings.self) private var appSettings`
- Bind Stepper to `appSettings.payCycleStartDay`

### Modified: `DashboardViewModel`

- Add `init(repo:appSettings:)`, store `private let appSettings: AppSettings`
- In `calculateMetrics()`, replace hardcoded calendar month start:
  ```swift
  // Before
  let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

  // After
  let (monthStart, _) = PayCycleService.currentFinancialMonth(startDay: appSettings.payCycleStartDay)
  ```
- `load()` stays param-free

### Modified: `CompassViewModel`

- Remove observable `payCycleStartDay` property
- Add `init(repo:appSettings:)`, store `private let appSettings: AppSettings`
- `computeHealthScore()` reads `appSettings.payCycleStartDay` directly
- `load()` stays param-free

### Modified: `TransactionListViewModel`

- Add `appSettings: AppSettings` to init
- When period is `.month`, pass `appSettings.payCycleStartDay` to `ChartDataService`

### Modified: `CategoryBreakdownViewModel`

- Add `appSettings: AppSettings` to init
- Pass `appSettings.payCycleStartDay` to `PieChartDataService` for `.month`

### Modified: `ChartDataService`

- `generateChartData(from:for:referenceDate:payCycleStartDay:)` — add `payCycleStartDay: Int = 1`
- `filterItems(_:for:referenceDate:payCycleStartDay:)`:
  - `.week` and `.year` — keep existing `timePeriod.days` arithmetic (no change)
  - `.month` — use `PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)` as the window
- `generateMonthlyData` — 4-week bucket grouping stays unchanged; only the filter boundary changes

### Modified: `PieChartDataService`

- Same `payCycleStartDay: Int = 1` parameter added to `generatePieChartData` and `filterItems`
- `.month` filter switches to `PayCycleService.currentFinancialMonth` window

---

## UI: Period Label Display

| Location | Change |
|----------|--------|
| `ProfilePayCycleSection` | Existing description text is correct. No change. |
| `DashboardView` "This month" | Add subtitle showing the actual window (e.g. "Jun 10 – Jun 20") when `payCycleStartDay != 1` |
| `ActivityView` Month picker | Show date range label under picker when financial month is active |
| `HealthScoreDetailView` | Already updated. No change. |

---

## Testing

### `PayCycleServiceTests` (new)
- `startDay = 1` matches calendar month boundaries
- `startDay = 28` handles Feb correctly (day 29/30/31 don't exist)
- Year boundary: Dec 10 → Jan 9 window
- `financialMonths(count: 6)` returns non-overlapping, contiguous, correctly ordered windows

### `ChartDataServiceTests` (new / expand)
- `.month` with `payCycleStartDay = 10`: transaction on day 9 of current calendar month excluded if before financial start; transaction on financial start day included
- `.week` and `.year` unaffected by `payCycleStartDay`

### `DashboardViewModelTests` (new)
- Transaction one day before financial start is excluded from `monthlyIncome` / `monthlyExpenses`
- Transaction on financial start day is included

### `FinancialHealthServiceTests` (existing)
- Update `makeService()` helper to inject `AppSettings` rather than a raw `Int`
- Test logic stays otherwise unchanged

### `AppSettingsTests` (new, small)
- UserDefaults round-trip: write `payCycleStartDay = 15`, re-init `AppSettings`, read back 15
- Default is 1 when key is absent

---

## Constraints

- Day range is 1–28 (not 1–31) to avoid months where e.g. day 31 doesn't exist
- `payCycleStartDay = 1` is identical to calendar month behaviour — existing users see no change
- No SwiftData schema migration required — this setting lives in UserDefaults only
