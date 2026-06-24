# Forecast Section Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the plain `ForecastCard` with a cumulative area/line chart backed by a persisted SwiftData sliding window cache that only recomputes new days on each app open.

**Architecture:** Data flows from `SpendingForecastService` (pure, testable, now returns a cache alongside the forecast) → `CompassViewModel` (reads/writes cache via repo) → `ForecastCard` (renders the chart using Swift Charts). `DailyForecastCache` is a SwiftData model stored alongside existing app models.

**Tech Stack:** SwiftUI, SwiftData, Swift Charts, Swift Testing

## Global Constraints

- Swift Testing only — `@Test`, `#expect`, `@testable import PersonalFinanceTraker`. No XCTest.
- Amounts stored as **negative** `Decimal` for expenses. `sumExpenses` calls `abs()`.
- EUR hardcoded. `CurrencyService().convertToBase(amount, from: "EUR")` returns the value unchanged.
- No SwiftData migration required — app is not on the App Store.
- Build and test via Xcode MCP tools only. Never run `xcodebuild` in Bash.
- `tabIdentifier` for all Xcode MCP calls: `"windowtab1"`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `PersonalFinanceTraker/PersonalFinanceTraker/Models/DailyForecastCache.swift` | SwiftData cache model |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/CompassDataModels.swift` | Add `DailyPoint`, extend `SpendingForecast` |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift` | Add 2 protocol methods + implementations |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift` | Register `DailyForecastCache` in Schema |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SpendingForecastService.swift` | Sliding window algorithm |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift` | Wire cache read/write in `computeForecast()` |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/ForecastCard.swift` | Chart redesign |
| Create | `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/SpendingForecastServiceTests.swift` | Sliding window tests |

---

## Task 1: Data models + Schema registration

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/CompassDataModels.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/DailyForecastCache.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`

**Interfaces:**
- Produces: `DailyPoint(day: Int, cumulative: Decimal)`, `SpendingForecast.dailyActuals: [DailyPoint]`, `DailyForecastCache(monthKey:computedUpToDay:days:amounts:)`

- [ ] **Step 1: Add `DailyPoint` and extend `SpendingForecast`**

In `CompassDataModels.swift`, append below the existing `// MARK: - Forecast` section:

```swift
struct DailyPoint: Identifiable {
    let id = UUID()
    let day: Int
    let cumulative: Decimal
}
```

Then change `SpendingForecast` from:
```swift
struct SpendingForecast {
    let projectedAmount: Decimal
    let dailyPace: Decimal
    let lastThreeMonthAvg: Decimal
    let daysLeft: Int
}
```
to:
```swift
struct SpendingForecast {
    let projectedAmount: Decimal
    let dailyPace: Decimal
    let lastThreeMonthAvg: Decimal
    let daysLeft: Int
    let dailyActuals: [DailyPoint]
}
```

- [ ] **Step 2: Create `DailyForecastCache.swift`**

```swift
import SwiftData

@Model
final class DailyForecastCache {
    var monthKey: String        // e.g. "2026-06"
    var computedUpToDay: Int    // last calendar day with actual data
    var days: [Int]             // [1, 2, 3, ...]
    var amounts: [Double]       // cumulative spend per day, base currency

    init(monthKey: String, computedUpToDay: Int, days: [Int], amounts: [Double]) {
        self.monthKey = monthKey
        self.computedUpToDay = computedUpToDay
        self.days = days
        self.amounts = amounts
    }
}
```

- [ ] **Step 3: Register `DailyForecastCache` in the Schema**

In `PersonalFinanceTrakerApp.swift`, find:
```swift
let schema = Schema([
    TransactionModel.self,
    CategoryModel.self,
    CreditCardModel.self,
    GoalModel.self,
    HealthScoreSnapshot.self,
])
```
Change to:
```swift
let schema = Schema([
    TransactionModel.self,
    CategoryModel.self,
    CreditCardModel.self,
    GoalModel.self,
    HealthScoreSnapshot.self,
    DailyForecastCache.self,
])
```

- [ ] **Step 4: Build to verify no compiler errors**

Load schema via ToolSearch:
```
query: "select:mcp__xcode__BuildProject"
```
Then call:
```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: Build succeeded.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/CompassDataModels.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/Models/DailyForecastCache.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift
git commit -m "feat: add DailyPoint, DailyForecastCache models; register in schema"
```

---

## Task 2: Repository — `fetchForecastCache` + `saveForecastCache`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift`

**Interfaces:**
- Consumes: `DailyForecastCache` from Task 1
- Produces: `ITransactionRepository.fetchForecastCache() throws -> DailyForecastCache?`, `ITransactionRepository.saveForecastCache(_ cache: DailyForecastCache) throws`

- [ ] **Step 1: Add methods to the protocol**

In `TransactionRepository.swift`, add to the `protocol ITransactionRepository` block after `fetchSnapshots`:

```swift
func fetchForecastCache() throws -> DailyForecastCache?
func saveForecastCache(_ cache: DailyForecastCache) throws
```

- [ ] **Step 2: Implement in `TransactionRepository`**

Append to the `TransactionRepository` extension (after `fetchSnapshots`):

```swift
func fetchForecastCache() throws -> DailyForecastCache? {
    try context.fetch(FetchDescriptor<DailyForecastCache>()).first
}

func saveForecastCache(_ cache: DailyForecastCache) throws {
    let existing = try context.fetch(FetchDescriptor<DailyForecastCache>())
    existing.forEach { context.delete($0) }
    context.insert(cache)
    try context.save()
}
```

- [ ] **Step 3: Build to verify**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: Build succeeded.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift
git commit -m "feat: add fetchForecastCache/saveForecastCache to repository"
```

---

## Task 3: `SpendingForecastService` — sliding window + tests

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SpendingForecastService.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/SpendingForecastServiceTests.swift`

**Interfaces:**
- Consumes: `DailyForecastCache` (Task 1), `DailyPoint` (Task 1)
- Produces: `SpendingForecastService.compute(expenseTransactions:cache:now:) -> (forecast: SpendingForecast, updatedCache: DailyForecastCache)`

- [ ] **Step 1: Write failing tests**

Create `SpendingForecastServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct SpendingForecastServiceTests {
    private let service = SpendingForecastService(currencyService: CurrencyService())
    private let cal = Calendar.current

    private func date(year: Int, month: Int, day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func tx(on date: Date, amount: Double) -> TransactionModel {
        TransactionModel(
            timestamp: date, amount: Decimal(amount),
            note: "", category: "Food", currencyCode: "EUR", goalId: nil
        )
    }

    @Test("nil cache computes all elapsed days")
    func nilCacheFullRecompute() {
        let now = date(year: 2026, month: 6, day: 15)
        let transactions = [
            tx(on: date(year: 2026, month: 6, day: 1), amount: -50),
            tx(on: date(year: 2026, month: 6, day: 10), amount: -30),
        ]

        let (forecast, cache) = service.compute(expenseTransactions: transactions, cache: nil, now: now)

        #expect(cache.monthKey == "2026-06")
        #expect(cache.computedUpToDay == 15)
        #expect(cache.days.count == 15)
        #expect(cache.amounts[0] == 50.0)   // day 1: 50
        #expect(cache.amounts[9] == 80.0)   // day 10: 50 + 30
        #expect(cache.amounts[14] == 80.0)  // day 15: no new spend
        #expect(forecast.dailyActuals.count == 15)
    }

    @Test("cache hit appends only days after computedUpToDay")
    func cacheHitAppendsNewDaysOnly() {
        let now = date(year: 2026, month: 6, day: 20)
        // Cache up to day 15, cumulative 100 at each entry (all spend on day 1)
        let existingCache = DailyForecastCache(
            monthKey: "2026-06",
            computedUpToDay: 15,
            days: Array(1...15),
            amounts: Array(repeating: 100.0, count: 15)
        )
        // New transaction on day 18: €40
        let transactions = [tx(on: date(year: 2026, month: 6, day: 18), amount: -40)]

        let (_, updatedCache) = service.compute(
            expenseTransactions: transactions, cache: existingCache, now: now
        )

        #expect(updatedCache.computedUpToDay == 20)
        #expect(updatedCache.days.count == 20)
        // days 16, 17, 19, 20 add 0; day 18 adds 40 → final = 140
        #expect(updatedCache.amounts.last == 140.0)
    }

    @Test("month boundary discards old cache and recomputes from day 1")
    func monthBoundaryFullRecompute() {
        let now = date(year: 2026, month: 7, day: 5)
        let juneCache = DailyForecastCache(
            monthKey: "2026-06",
            computedUpToDay: 30,
            days: Array(1...30),
            amounts: Array(1...30).map { Double($0) * 10.0 }
        )
        let transactions = [tx(on: date(year: 2026, month: 7, day: 1), amount: -20)]

        let (_, updatedCache) = service.compute(
            expenseTransactions: transactions, cache: juneCache, now: now
        )

        #expect(updatedCache.monthKey == "2026-07")
        #expect(updatedCache.days.count == 5)
        #expect(updatedCache.amounts[0] == 20.0)  // fresh cumulative from July 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Load schema:
```
query: "select:mcp__xcode__RunSomeTests"
```
Then:
```
mcp__xcode__RunSomeTests(
    tabIdentifier: "windowtab1",
    testIDs: ["PersonalFinanceTrakerTests/SpendingForecastServiceTests"]
)
```
Expected: FAIL — `compute` does not yet accept `cache` or `now` parameters.

- [ ] **Step 3: Implement the sliding window in `SpendingForecastService.swift`**

Replace the entire file content with:

```swift
import Foundation

struct SpendingForecastService {
    let currencyService: CurrencyService

    func compute(
        expenseTransactions: [TransactionModel],
        cache: DailyForecastCache?,
        now: Date = .now
    ) -> (forecast: SpendingForecast, updatedCache: DailyForecastCache) {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysElapsed = max(1, calendar.dateComponents([.day], from: startOfMonth, to: now).day ?? 1)
        let daysLeft = max(0, daysInMonth - daysElapsed)
        let currentMonthKey = monthKey(for: now)

        // Sliding window setup
        let cacheIsValid = cache != nil
            && cache!.monthKey == currentMonthKey
            && cache!.computedUpToDay < daysElapsed
        let cacheIsUpToDate = cache != nil
            && cache!.monthKey == currentMonthKey
            && cache!.computedUpToDay >= daysElapsed

        var days: [Int]
        var amounts: [Double]
        let startDay: Int
        var runningTotal: Double

        if cacheIsUpToDate {
            // Nothing new — reuse as-is
            days = cache!.days
            amounts = cache!.amounts
            startDay = daysElapsed + 1  // loop won't execute
            runningTotal = amounts.last ?? 0
        } else if cacheIsValid {
            days = cache!.days
            amounts = cache!.amounts
            startDay = cache!.computedUpToDay + 1
            runningTotal = amounts.last ?? 0
        } else {
            // Full recompute (nil cache or month boundary)
            days = []
            amounts = []
            startDay = 1
            runningTotal = 0
        }

        // Compute new days (startDay..daysElapsed)
        if startDay <= daysElapsed {
            for day in startDay...daysElapsed {
                let dayStart = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) ?? startOfMonth
                let dayEnd   = calendar.date(byAdding: .day, value: day,     to: startOfMonth) ?? startOfMonth
                let dayTotal = sumExpenses(
                    expenseTransactions.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                )
                runningTotal += NSDecimalNumber(decimal: dayTotal).doubleValue
                days.append(day)
                amounts.append(runningTotal)
            }
        }

        // Build DailyPoint array for chart
        let dailyActuals: [DailyPoint] = zip(days, amounts).map { day, amount in
            DailyPoint(day: day, cumulative: Decimal(string: String(amount)) ?? Decimal(amount))
        }

        // Aggregate forecast metrics (unchanged logic)
        let currentMonthExpenses = sumExpenses(expenseTransactions.filter { $0.timestamp >= startOfMonth })
        let dailyPace = currentMonthExpenses / Decimal(daysElapsed)
        let projected = dailyPace * Decimal(daysInMonth)

        let threeMonthTotal = (1...3).reduce(Decimal(0)) { total, offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: startOfMonth) ?? startOfMonth
            let end   = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return total + sumExpenses(expenseTransactions.filter { $0.timestamp >= start && $0.timestamp < end })
        }
        let lastThreeMonthAvg = threeMonthTotal / 3

        let forecast = SpendingForecast(
            projectedAmount: projected,
            dailyPace: dailyPace,
            lastThreeMonthAvg: lastThreeMonthAvg,
            daysLeft: daysLeft,
            dailyActuals: dailyActuals
        )
        let updatedCache = DailyForecastCache(
            monthKey: currentMonthKey,
            computedUpToDay: daysElapsed,
            days: days,
            amounts: amounts
        )
        return (forecast, updatedCache)
    }

    // MARK: - Private

    private func monthKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(String(format: "%02d", comps.month ?? 0))"
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(
    tabIdentifier: "windowtab1",
    testIDs: ["PersonalFinanceTrakerTests/SpendingForecastServiceTests"]
)
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SpendingForecastService.swift \
        PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/SpendingForecastServiceTests.swift
git commit -m "feat: sliding window cache in SpendingForecastService; add tests"
```

---

## Task 4: ViewModel wiring

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`

**Interfaces:**
- Consumes: `repo.fetchForecastCache()` (Task 2), `forecastService.compute(expenseTransactions:cache:)` (Task 3), `repo.saveForecastCache(_:)` (Task 2)

- [ ] **Step 1: Update `computeForecast()` in `CompassViewModel`**

Find the existing method:
```swift
private func computeForecast() {
    forecast = forecastService.compute(expenseTransactions: expenseTransactions)
}
```
Replace with:
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

- [ ] **Step 2: Build and verify**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: Build succeeded. (The old `compute(expenseTransactions:)` call is gone; the new signature matches.)

- [ ] **Step 3: Run all tests to confirm no regressions**

Load schema:
```
query: "select:mcp__xcode__RunAllTests"
```
Then:
```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift
git commit -m "feat: wire forecast cache read/write in CompassViewModel"
```

---

## Task 5: `ForecastCard` redesign

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/ForecastCard.swift`

**Interfaces:**
- Consumes: `SpendingForecast.dailyActuals: [DailyPoint]` (Task 1), `forecast.projectedAmount`, `forecast.lastThreeMonthAvg`, `forecast.daysLeft`

- [ ] **Step 1: Replace `ForecastCard.swift` with chart redesign**

```swift
import SwiftUI
import Charts

struct ForecastCard: View {
    let forecast: SpendingForecast

    private struct ChartPoint: Identifiable {
        var id: Int { day }
        let day: Int
        let amount: Double
    }

    private var isOverPace: Bool {
        forecast.lastThreeMonthAvg > 0 && forecast.projectedAmount > forecast.lastThreeMonthAvg
    }
    private var trendColor: Color { isOverPace ? .negative : .positive }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: .now)?.count ?? 30
    }

    private var actualPoints: [ChartPoint] {
        forecast.dailyActuals.map {
            ChartPoint(day: $0.day, amount: NSDecimalNumber(decimal: $0.cumulative).doubleValue)
        }
    }

    // Two-point segment: last actual → projected month-end
    private var projectionPoints: [ChartPoint] {
        guard let last = actualPoints.last else { return [] }
        return [
            last,
            ChartPoint(
                day: daysInMonth,
                amount: NSDecimalNumber(decimal: forecast.projectedAmount).doubleValue
            ),
        ]
    }

    var body: some View {
        GlassCard(tint: trendColor) {
            VStack(alignment: .leading, spacing: 14) {
                // Header row
                HStack {
                    Label("At this pace", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(forecast.daysLeft) days left")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Chart (only rendered when we have data)
                if !actualPoints.isEmpty {
                    Chart {
                        // Solid area + line for actual days
                        ForEach(actualPoints) { point in
                            AreaMark(
                                x: .value("Day", point.day),
                                y: .value("Spend", point.amount)
                            )
                            .foregroundStyle(trendColor.opacity(0.2))
                            LineMark(
                                x: .value("Day", point.day),
                                y: .value("Spend", point.amount),
                                series: .value("Series", "actual")
                            )
                            .foregroundStyle(trendColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }

                        // Dashed projection segment (last actual → month-end)
                        ForEach(projectionPoints) { point in
                            LineMark(
                                x: .value("Day", point.day),
                                y: .value("Spend", point.amount),
                                series: .value("Series", "projection")
                            )
                            .foregroundStyle(trendColor.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }

                        // 3-month average reference line
                        if forecast.lastThreeMonthAvg > 0 {
                            let avg = NSDecimalNumber(decimal: forecast.lastThreeMonthAvg).doubleValue
                            RuleMark(y: .value("Avg", avg))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("avg")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                        }
                    }
                    .frame(height: 90)
                    .chartXScale(domain: 1...daysInMonth)
                    .chartXAxis {
                        AxisMarks(values: [1, daysInMonth]) { value in
                            AxisValueLabel {
                                if let day = value.as(Int.self) {
                                    Text("\(day)")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                }

                Divider().overlay(Color.white.opacity(0.2))

                // Summary row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(forecast.projectedAmount.formattedEUR())
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("projected this month")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    let diff = forecast.projectedAmount - forecast.lastThreeMonthAvg
                    if diff != 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(diff > 0
                                ? "+\(diff.formattedEUR())"
                                : "-\(abs(diff).formattedEUR())"
                            )
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            Text("vs 3-month avg")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: Build succeeded.

- [ ] **Step 3: Run all tests**

```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/ForecastCard.swift
git commit -m "feat: redesign ForecastCard with cumulative area/line chart"
```
