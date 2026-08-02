# Recurring Transactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user mark a transaction as recurring (weekly/monthly/yearly) and have future occurrences appear automatically as real transactions, without re-entering them by hand.

**Architecture:** A new `RecurrenceRule` SwiftData model holds the recurrence template. A pure, SwiftData-free `RecurrenceOccurrenceCalculator` computes due occurrence dates (the riskiest logic — month/leap-day clamping). A `RecurrenceMaterializationService`, triggered from `MainTabView`'s existing launch/foreground hooks (no background task), turns due occurrences into ordinary `TransactionModel` rows tagged with a `recurrenceRuleId` back-link. Editing/deleting a materialized transaction offers "This transaction" vs. "This and future" — past rows are never rewritten.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`@Test`/`#expect`, not XCTest).

## Global Constraints

- Expenses are stored as **negative** `Decimal`; convert to `Double` only for display.
- Currency is **EUR**, hardcoded throughout (`currencyCode` fields default to `"EUR"`).
- Tests use **Swift Testing** (`@Test`, `#expect`), not XCTest; `@testable import PersonalFinanceTraker`.
- **Never run `xcodebuild` or `swift test` in Bash.** Use the Xcode MCP tools only: first `ToolSearch` with `query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"`, then call the tool with `tabIdentifier: "windowtab1"`.
- No SwiftData migration path needed for the new model/fields — this project isn't on the App Store; reinstall during development (per project's migration policy).
- Follow existing patterns: enums backing a `@Model` property are stored as a raw `String` with a computed accessor (see `CategoryModel.type` / `.transactionType`), not as a native SwiftData enum.
- `RecurrenceRule`'s back-link on `TransactionModel` is a `UUID`, never a `PersistentIdentifier` — `PersistentIdentifier` isn't stable across store rebuilds and this project's migration policy assumes reinstalls. `UUID` is the same choice already made for `goalId`.

---

## File Structure

**New:**
- `Models/RecurrenceFrequency.swift` — `weekly`/`monthly`/`yearly` enum with display labels.
- `Models/RecurrenceOccurrenceCalculator.swift` — pure occurrence-date generator (no SwiftData).
- `Models/RecurrenceRule.swift` — SwiftData `@Model` for the recurrence template.
- `Utilities/RecurrenceMaterializationService.swift` — turns due occurrences into `TransactionModel` rows.
- `PersonalFinanceTrakerTests/Models/RecurrenceOccurrenceCalculatorTests.swift`
- `PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift`
- `PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift`
- `PersonalFinanceTrakerTests/Utilities/RecurrenceMaterializationServiceTests.swift`

**Modified:**
- `Models/TransactionModel.swift` — add `recurrenceRuleId: UUID?`.
- `Models/Snapshots.swift` — `TransactionSnapshot`/`TransactionInput` gain `recurrenceRuleId`; add `RecurrenceRuleSnapshot`/`RecurrenceRuleInput`.
- `Models/TransactionRepository.swift` (`ITransactionRepository`) — add 7 recurrence-rule methods.
- `Models/TransactionActor.swift` — thread `recurrenceRuleId` through existing transaction methods; implement the 7 new methods.
- `App/AppContainer.swift` — register `RecurrenceRule.self` in the schema.
- `PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift` — stub the 7 new methods.
- `PersonalFinanceTrakerTests/Mocks/TransactionSnapshotFactory.swift` — add `RecurrenceRuleSnapshot.test(...)`, register `RecurrenceRule.self` in the shared test schema.
- `Features/MainTabView/MainTabView.swift` — call `materialize()` from `.task` and `scenePhase == .active`.
- `Features/EditAddTransactionView/EditAddTransactionViewModel.swift` — Repeat toggle state, `buildRecurrenceRuleInput()`, `saveRecurringTransaction()`, `fetchRecurrenceRule`-backed "this and future" support.
- `Features/EditAddTransactionView/Components/TransactionFormView.swift` — Repeat toggle + frequency/interval picker (new transactions only).
- `Features/EditAddTransactionView/EditAddTransactionView.swift` — "This transaction" / "This and future" confirmation dialog on save/delete of a recurring transaction.
- `PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift` — new tests for the above.

---

### Task 1: `RecurrenceFrequency` + `RecurrenceOccurrenceCalculator`

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceFrequency.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceOccurrenceCalculator.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceOccurrenceCalculatorTests.swift`

**Interfaces:**
- Produces: `enum RecurrenceFrequency: String, CaseIterable, Sendable { case weekly, monthly, yearly }` with `var label: String`, `func unitLabel(for interval: Int) -> String`, and `var maxInterval: Int` (UI Stepper bound, per frequency).
- Produces: `enum RecurrenceOccurrenceCalculator { static func occurrenceDates(frequency: RecurrenceFrequency, interval: Int, startDate: Date, ruleEndDate: Date?, since: Date?, through: Date, calendar: Calendar = .current) -> [Date] }`.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceOccurrenceCalculatorTests.swift`:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceOccurrenceCalculatorTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func monthlyRuleStartingJan31ClampsToMonthEnd() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 31),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 4, 30),
            calendar: calendar
        )
        #expect(dates == [date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)])
    }

    @Test func monthlyClampDoesNotDriftTheFollowingMonth() {
        // Feb 28 (clamped from Jan 31) must not become the new anchor day for March.
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 31),
            ruleEndDate: nil,
            since: date(2026, 2, 28),
            through: date(2026, 3, 31),
            calendar: calendar
        )
        #expect(dates == [date(2026, 3, 31)])
    }

    @Test func yearlyLeapDayClampsToFeb28OnNonLeapYear() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .yearly,
            interval: 1,
            startDate: date(2024, 2, 29),
            ruleEndDate: nil,
            since: nil,
            through: date(2025, 12, 31),
            calendar: calendar
        )
        #expect(dates == [date(2024, 2, 29), date(2025, 2, 28)])
    }

    @Test func weeklyEveryTwoWeeks() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .weekly,
            interval: 2,
            startDate: date(2026, 3, 2),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(dates == [date(2026, 3, 2), date(2026, 3, 16), date(2026, 3, 30)])
    }

    @Test func monthlyEveryThreeMonthsWithClamping() {
        // interval > 2, combined with month-end clamping, to cover UI intervals beyond weekly/2.
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 3,
            startDate: date(2026, 1, 31),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 10, 31),
            calendar: calendar
        )
        #expect(dates == [date(2026, 1, 31), date(2026, 4, 30), date(2026, 7, 31), date(2026, 10, 31)])
    }

    @Test func sinceCursorExcludesAlreadyMaterializedOccurrence() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            ruleEndDate: nil,
            since: date(2026, 2, 1),
            through: date(2026, 3, 1),
            calendar: calendar
        )
        #expect(dates == [date(2026, 3, 1)])
    }

    @Test func ruleEndDateStopsGeneratingFurtherOccurrences() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            ruleEndDate: date(2026, 1, 15),
            since: nil,
            through: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(dates == [date(2026, 1, 1)])
    }

    @Test func noOccurrencesWhenThroughIsBeforeStartDate() {
        let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 5, 1),
            ruleEndDate: nil,
            since: nil,
            through: date(2026, 4, 1),
            calendar: calendar
        )
        #expect(dates.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Load the MCP schema, then run:
```
ToolSearch(query: "select:mcp__xcode__BuildProject,mcp__xcode__RunSomeTests")
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/RecurrenceOccurrenceCalculatorTests"])
```
Expected: build FAILS — `RecurrenceFrequency` and `RecurrenceOccurrenceCalculator` don't exist yet.

- [ ] **Step 3: Implement `RecurrenceFrequency`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceFrequency.swift`:

```swift
import Foundation

enum RecurrenceFrequency: String, CaseIterable, Sendable {
    case weekly
    case monthly
    case yearly

    var label: String {
        switch self {
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        }
    }

    func unitLabel(for interval: Int) -> String {
        switch self {
        case .weekly: interval == 1 ? String(localized: "week") : String(localized: "weeks")
        case .monthly: interval == 1 ? String(localized: "month") : String(localized: "months")
        case .yearly: interval == 1 ? String(localized: "year") : String(localized: "years")
        }
    }

    /// Upper bound for the interval Stepper — keeps "every N <unit>" in a sane range per
    /// frequency (e.g. not "every 52 years"). The calculator itself has no such limit.
    var maxInterval: Int {
        switch self {
        case .weekly: 52
        case .monthly: 24
        case .yearly: 10
        }
    }
}
```

- [ ] **Step 4: Implement `RecurrenceOccurrenceCalculator`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceOccurrenceCalculator.swift`:

```swift
import Foundation

/// Pure calendar-anchored occurrence-date generator — no SwiftData, so month-end/leap-day
/// edge cases (the riskiest part of recurring transactions) can be tested without a model context.
enum RecurrenceOccurrenceCalculator {
    /// Every occurrence strictly after `since` (or from `startDate` itself when `since` is nil),
    /// up to and including `through`, clipped by `ruleEndDate` if set.
    ///
    /// Each occurrence is computed independently from `startDate` (not by repeatedly advancing
    /// the previous occurrence), so a clamped date — e.g. Jan 31 -> Feb 28 for a monthly rule —
    /// never becomes the new anchor day for the following month.
    static func occurrenceDates(
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        ruleEndDate: Date?,
        since: Date?,
        through: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard interval > 0 else { return [] }
        let cutoff = ruleEndDate.map { min($0, through) } ?? through
        guard startDate <= cutoff else { return [] }

        var dates: [Date] = []
        var n = 0
        // Safety valve, not a user-facing limit: 10,000 weekly occurrences is ~190 years.
        while n < 10_000 {
            guard let occurrence = occurrenceDate(for: n, frequency: frequency, interval: interval, startDate: startDate, calendar: calendar) else { break }
            if occurrence > cutoff { break }
            if since == nil || occurrence > since! {
                dates.append(occurrence)
            }
            n += 1
        }
        return dates
    }

    private static func occurrenceDate(for n: Int, frequency: RecurrenceFrequency, interval: Int, startDate: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: n * interval * 7, to: startDate)
        case .monthly:
            return addingClampedMonths(n * interval, to: startDate, calendar: calendar)
        case .yearly:
            return addingClampedMonths(n * interval * 12, to: startDate, calendar: calendar)
        }
    }

    /// Adds calendar months anchored to `startDate`'s day-of-month, clamping to the target
    /// month's last day when it's shorter (e.g. Jan 31 + 1 month -> Feb 28/29).
    private static func addingClampedMonths(_ months: Int, to date: Date, calendar: Calendar) -> Date {
        guard months != 0 else { return date }
        let day = calendar.component(.day, from: date)
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.month = (comps.month ?? 1) + months
        guard let firstOfTargetMonth = calendar.date(from: comps) else { return date }
        let dayRange = calendar.range(of: .day, in: .month, for: firstOfTargetMonth) ?? (1..<29)

        var targetComps = calendar.dateComponents([.year, .month], from: firstOfTargetMonth)
        targetComps.day = min(day, dayRange.count)
        targetComps.hour = time.hour
        targetComps.minute = time.minute
        targetComps.second = time.second
        return calendar.date(from: targetComps) ?? date
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/RecurrenceOccurrenceCalculatorTests"])
```
Expected: PASS (8/8).

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceFrequency.swift PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceOccurrenceCalculator.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceOccurrenceCalculatorTests.swift
git commit -m "feat: add recurrence occurrence-date calculator with month/leap-day clamping"
```

---

### Task 2: `RecurrenceRule` model + schema registration

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceRule.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift`

**Interfaces:**
- Consumes: `RecurrenceFrequency` (Task 1).
- Produces: `@Model final class RecurrenceRule` with `id: UUID`, `frequency/interval/startDate/endDate/lastMaterializedDate`, template fields (`amount/note/category/currencyCode/goalId`), `categoryModel: CategoryModel?` relationship, computed `recurrenceFrequency: RecurrenceFrequency`, `func isActive(asOf: Date) -> Bool`.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift`:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceRuleTests {
    private func makeRule(endDate: Date? = nil) -> RecurrenceRule {
        RecurrenceRule(
            frequency: .yearly,
            interval: 1,
            startDate: .now,
            endDate: endDate,
            amount: -10,
            note: "Test",
            category: "Food",
            currencyCode: "EUR"
        )
    }

    @Test func recurrenceFrequencyDecodesRawValue() {
        #expect(makeRule().recurrenceFrequency == .yearly)
    }

    @Test func isActiveWhenEndDateIsNil() {
        #expect(makeRule().isActive(asOf: .now) == true)
    }

    @Test func isActiveWhenEndDateIsInTheFuture() {
        let future = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        #expect(makeRule(endDate: future).isActive(asOf: .now) == true)
    }

    @Test func notActiveWhenEndDateIsInThePast() {
        let past = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        #expect(makeRule(endDate: past).isActive(asOf: .now) == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/RecurrenceRuleTests"])
```
Expected: build FAILS — `RecurrenceRule` doesn't exist yet.

- [ ] **Step 3: Implement `RecurrenceRule`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceRule.swift`:

```swift
import Foundation
import SwiftData

@Model
final class RecurrenceRule {
    @Attribute(.unique) var id: UUID
    var frequency: String // RecurrenceFrequency raw value — see CategoryModel.type for the same pattern
    var interval: Int
    var startDate: Date
    var endDate: Date?              // nil = open-ended / active
    var lastMaterializedDate: Date? // catch-up cursor; nil = never materialized

    // Transaction template — mirrors TransactionInput
    var amount: Decimal
    var note: String
    var category: String
    var currencyCode: String
    var goalId: UUID?

    @Relationship(deleteRule: .nullify)
    var categoryModel: CategoryModel?

    init(
        id: UUID = UUID(),
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date? = nil,
        lastMaterializedDate: Date? = nil,
        amount: Decimal,
        note: String,
        category: String,
        currencyCode: String,
        goalId: UUID? = nil,
        categoryModel: CategoryModel? = nil
    ) {
        self.id = id
        self.frequency = frequency.rawValue
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.lastMaterializedDate = lastMaterializedDate
        self.amount = amount
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.categoryModel = categoryModel
    }

    var recurrenceFrequency: RecurrenceFrequency {
        RecurrenceFrequency(rawValue: frequency) ?? .monthly
    }

    func isActive(asOf date: Date) -> Bool {
        endDate == nil || endDate! >= date
    }
}
```

- [ ] **Step 4: Register the model in the app's schema**

In `PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift`, add `RecurrenceRule.self` to the schema array:

```swift
        let schema = Schema([
            TransactionModel.self,
            CategoryModel.self,
            CreditCardModel.self,
            GoalModel.self,
            HealthScoreSnapshot.self,
            DailyForecastCache.self,
            RecurrenceRule.self,
        ])
```

- [ ] **Step 5: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/RecurrenceRuleTests"])
```
Expected: PASS (4/4).

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceRule.swift PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift
git commit -m "feat: add RecurrenceRule SwiftData model"
```

---

### Task 3: `TransactionModel` back-link + `Snapshots.swift` shapes

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionModel.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/Snapshots.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift` (append)

**Interfaces:**
- Consumes: `RecurrenceRule`, `RecurrenceFrequency` (Task 2).
- Produces: `TransactionModel.recurrenceRuleId: UUID?`; `TransactionSnapshot.recurrenceRuleId: UUID?`; `TransactionInput.recurrenceRuleId: UUID?` (defaults to `nil`); `RecurrenceRuleSnapshot` (`Identifiable, Sendable, Hashable`, `init(_ model: RecurrenceRule)`); `RecurrenceRuleInput` (`Sendable`, carries its own `id: UUID`).

- [ ] **Step 1: Write the failing test**

Append to `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift`:

```swift
struct TransactionSnapshotRecurrenceTests {
    @Test func snapshotCarriesRecurrenceRuleIdFromModel() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: TransactionModel.self, configurations: config)
        let ctx = ModelContext(container)
        let ruleId = UUID()
        let model = TransactionModel(
            timestamp: .now, amount: -10, note: "Rent", category: "Housing",
            currencyCode: "EUR", goalId: nil, recurrenceRuleId: ruleId
        )
        ctx.insert(model)
        try! ctx.save()

        #expect(TransactionSnapshot(model).recurrenceRuleId == ruleId)
    }
}
```

Add `import SwiftData` to the top of `RecurrenceRuleTests.swift` if not already present.

- [ ] **Step 2: Run test to verify it fails**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/TransactionSnapshotRecurrenceTests"])
```
Expected: build FAILS — `TransactionModel` has no `recurrenceRuleId` parameter/property yet.

- [ ] **Step 3: Add the back-link to `TransactionModel`**

In `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionModel.swift`, add the field and thread it through `init`:

```swift
    var goalId: UUID?
    var recurrenceRuleId: UUID?
```

```swift
    init(timestamp: Date,
         amount: Decimal,
         note: String,
         category: String,
         idCategory: String? = nil,
         categoryModel: CategoryModel? = nil,
         currencyCode: String = "EUR",
         goalId: UUID? = nil,
         recurrenceRuleId: UUID? = nil) {
        self.timestamp = timestamp
        self.amount = amount
        self.note = note
        self.category = category
        self.idCategory = idCategory
        self.categoryModel = categoryModel
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.recurrenceRuleId = recurrenceRuleId
    }
```

- [ ] **Step 4: Extend `Snapshots.swift`**

In `PersonalFinanceTraker/PersonalFinanceTraker/Models/Snapshots.swift`:

Add `recurrenceRuleId` to `TransactionSnapshot`:

```swift
struct TransactionSnapshot: Identifiable, Sendable, Hashable {
    let id: PersistentIdentifier
    let timestamp: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let recurrenceRuleId: UUID?
    let categoryId: PersistentIdentifier?
    let categorySystemImage: String?
    let categoryColorToken: String?

    init(_ model: TransactionModel) {
        self.id = model.persistentModelID
        self.timestamp = model.timestamp
        self.amount = model.amount
        self.note = model.note
        self.category = model.category
        self.currencyCode = model.currencyCode
        self.goalId = model.goalId
        self.recurrenceRuleId = model.recurrenceRuleId
        self.categoryId = model.categoryModel?.persistentModelID
        self.categorySystemImage = model.categoryModel?.systemImage
        self.categoryColorToken = model.categoryModel?.colorToken
    }
}
```

Add `recurrenceRuleId` to `TransactionInput`:

```swift
struct TransactionInput: Sendable {
    let timestamp: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let categoryPersistentId: PersistentIdentifier?
    let recurrenceRuleId: UUID?

    init(timestamp: Date, amount: Decimal, note: String, category: String, currencyCode: String, goalId: UUID? = nil, categoryPersistentId: PersistentIdentifier? = nil, recurrenceRuleId: UUID? = nil) {
        self.timestamp = timestamp
        self.amount = amount
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.categoryPersistentId = categoryPersistentId
        self.recurrenceRuleId = recurrenceRuleId
    }
}
```

Add two new types after `GoalInput`:

```swift
struct RecurrenceRuleSnapshot: Identifiable, Sendable, Hashable {
    let id: UUID
    let persistentId: PersistentIdentifier
    let frequency: RecurrenceFrequency
    let interval: Int
    let startDate: Date
    let endDate: Date?
    let lastMaterializedDate: Date?
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let categoryId: PersistentIdentifier?

    init(_ model: RecurrenceRule) {
        self.id = model.id
        self.persistentId = model.persistentModelID
        self.frequency = model.recurrenceFrequency
        self.interval = model.interval
        self.startDate = model.startDate
        self.endDate = model.endDate
        self.lastMaterializedDate = model.lastMaterializedDate
        self.amount = model.amount
        self.note = model.note
        self.category = model.category
        self.currencyCode = model.currencyCode
        self.goalId = model.goalId
        self.categoryId = model.categoryModel?.persistentModelID
    }
}

struct RecurrenceRuleInput: Sendable {
    let id: UUID
    let frequency: RecurrenceFrequency
    let interval: Int
    let startDate: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let categoryPersistentId: PersistentIdentifier?

    init(id: UUID = UUID(), frequency: RecurrenceFrequency, interval: Int, startDate: Date, amount: Decimal, note: String, category: String, currencyCode: String, goalId: UUID? = nil, categoryPersistentId: PersistentIdentifier? = nil) {
        self.id = id
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.amount = amount
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.categoryPersistentId = categoryPersistentId
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/TransactionSnapshotRecurrenceTests"])
```
Expected: PASS.

- [ ] **Step 6: Run the full test suite to check for regressions**

```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```
Expected: PASS — existing `TransactionInput`/`TransactionModel` call sites all use named arguments with the new params defaulted, so nothing else should break.

- [ ] **Step 7: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionModel.swift PersonalFinanceTraker/PersonalFinanceTraker/Models/Snapshots.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/RecurrenceRuleTests.swift
git commit -m "feat: add recurrenceRuleId back-link and recurrence rule snapshot/input types"
```

---

### Task 4: Repository protocol + `TransactionActor` implementation

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift`

**Interfaces:**
- Consumes: `RecurrenceRule`, `RecurrenceRuleSnapshot`, `RecurrenceRuleInput` (Tasks 2–3).
- Produces on `ITransactionRepository` (and `TransactionActor`):
  - `func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws`
  - `func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot]`
  - `func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot?`
  - `func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws`
  - `func closeRecurrenceRule(id: UUID, endDate: Date) async throws`
  - `func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws`
  - `func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws`

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

struct TransactionActorRecurrenceTests {
    private func makeActor() -> TransactionActor {
        let schema = Schema([TransactionModel.self, CategoryModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return TransactionActor(modelContainer: container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func ruleInput(startDate: Date) -> RecurrenceRuleInput {
        RecurrenceRuleInput(frequency: .monthly, interval: 1, startDate: startDate, amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR")
    }

    @Test func addAndFetchActiveRecurrenceRule() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let active = try await actor.fetchActiveRecurrenceRules()
        #expect(active.count == 1)
        #expect(active[0].id == input.id)
        #expect(active[0].frequency == .monthly)
    }

    @Test func fetchActiveExcludesRulesClosedInThePast() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)
        try await actor.closeRecurrenceRule(id: input.id, endDate: date(2026, 1, 15))

        // fetchActiveRecurrenceRules compares against "now", so a rule closed in 2026-01
        // stays excluded as long as the test runs after that date.
        let active = try await actor.fetchActiveRecurrenceRules()
        #expect(active.isEmpty)
    }

    @Test func fetchRecurrenceRuleById() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let fetched = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(fetched?.id == input.id)
        #expect(try await actor.fetchRecurrenceRule(id: UUID()) == nil)
    }

    @Test func materializeOccurrencesInsertsTaggedTransactionsAndAdvancesCursor() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let txInputs = [
            TransactionInput(timestamp: date(2026, 1, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id),
            TransactionInput(timestamp: date(2026, 2, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id)
        ]
        try await actor.materializeOccurrences(ruleId: input.id, inputs: txInputs, newCursor: date(2026, 2, 1))

        let all = try await actor.fetchAll()
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.recurrenceRuleId == input.id })

        let rule = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(rule?.lastMaterializedDate == date(2026, 2, 1))
    }

    @Test func updateRecurrenceRuleMutatesTemplateInPlace() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)

        let updated = RecurrenceRuleInput(id: input.id, frequency: .monthly, interval: 1, startDate: input.startDate, amount: -1500, note: "Rent (increased)", category: "Housing", currencyCode: "EUR")
        try await actor.updateRecurrenceRule(id: input.id, with: updated)

        let rule = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(rule?.amount == -1500)
        #expect(rule?.note == "Rent (increased)")
        #expect(rule?.startDate == input.startDate) // unchanged — v1 edit UI never changes cadence
    }

    @Test func deleteOccurrencesRemovesRowsAndResetsCursor() async throws {
        let actor = makeActor()
        let input = ruleInput(startDate: date(2026, 1, 1))
        try await actor.addRecurrenceRule(input)
        try await actor.materializeOccurrences(
            ruleId: input.id,
            inputs: [
                TransactionInput(timestamp: date(2026, 1, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id),
                TransactionInput(timestamp: date(2026, 2, 1), amount: -1200, note: "Rent", category: "Housing", currencyCode: "EUR", recurrenceRuleId: input.id)
            ],
            newCursor: date(2026, 2, 1)
        )

        try await actor.deleteOccurrences(recurrenceRuleId: input.id, from: date(2026, 2, 1))

        let all = try await actor.fetchAll()
        #expect(all.count == 1) // January row survives, February row (>= cutoff) is removed
        #expect(all[0].timestamp == date(2026, 1, 1))

        let rule = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(rule!.lastMaterializedDate! < date(2026, 2, 1))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/TransactionActorRecurrenceTests"])
```
Expected: build FAILS — the protocol/actor methods don't exist yet.

- [ ] **Step 3: Extend the protocol**

In `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift`, add to `ITransactionRepository`:

```swift
    // Recurrence rules
    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws
    func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot]
    func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot?
    func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws
    func closeRecurrenceRule(id: UUID, endDate: Date) async throws
    func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws
    func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws
```

- [ ] **Step 4: Thread `recurrenceRuleId` through existing `TransactionActor` methods**

In `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`, update `add`, `addBatch`, and `update` to pass `recurrenceRuleId` into `TransactionModel`:

```swift
    func add(_ input: TransactionInput) async throws {
        let model = TransactionModel(
            timestamp: input.timestamp,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            recurrenceRuleId: input.recurrenceRuleId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        }
        modelContext.insert(model)
        try modelContext.save()
    }

    func addBatch(_ inputs: [TransactionInput]) async throws {
        for input in inputs {
            let model = TransactionModel(
                timestamp: input.timestamp,
                amount: input.amount,
                note: input.note,
                category: input.category,
                currencyCode: input.currencyCode,
                goalId: input.goalId,
                recurrenceRuleId: input.recurrenceRuleId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func update(id: PersistentIdentifier, with input: TransactionInput) async throws {
        guard let model = modelContext.model(for: id) as? TransactionModel else { return }
        model.timestamp = input.timestamp
        model.amount = input.amount
        model.note = input.note
        model.category = input.category
        model.currencyCode = input.currencyCode
        model.goalId = input.goalId
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            model.categoryModel = cat
        } else {
            model.categoryModel = nil
        }
        try modelContext.save()
    }
```

(`update` deliberately does not overwrite `recurrenceRuleId` — a single "this transaction" edit never changes which rule a row belongs to.)

- [ ] **Step 5: Implement the 7 new methods**

Add to `TransactionActor`, e.g. after the `update` method:

```swift
    // MARK: Recurrence rules

    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws {
        let rule = RecurrenceRule(
            id: input.id,
            frequency: input.frequency,
            interval: input.interval,
            startDate: input.startDate,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId
        )
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            rule.categoryModel = cat
        }
        modelContext.insert(rule)
        try modelContext.save()
    }

    func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot] {
        let today = Calendar.current.startOfDay(for: .now)
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        return all.filter { $0.isActive(asOf: today) }.map(RecurrenceRuleSnapshot.init)
    }

    func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot? {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return try modelContext.fetch(desc).first.map(RecurrenceRuleSnapshot.init)
    }

    func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.amount = input.amount
        rule.note = input.note
        rule.category = input.category
        rule.currencyCode = input.currencyCode
        rule.goalId = input.goalId
        if let pid = input.categoryPersistentId,
           let cat = modelContext.model(for: pid) as? CategoryModel {
            rule.categoryModel = cat
        } else {
            rule.categoryModel = nil
        }
        try modelContext.save()
    }

    func closeRecurrenceRule(id: UUID, endDate: Date) async throws {
        var desc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        guard let rule = try modelContext.fetch(desc).first else { return }
        rule.endDate = endDate
        try modelContext.save()
    }

    /// Deletes already-materialized rows for this rule at/after `cutoffDate` (not "future"
    /// rows in the un-materialized sense — every row in the table is materialized). Used to
    /// wipe out rows created under an old template so the next materialize pass regenerates
    /// them under the new one; see the re-entrancy note on RecurrenceMaterializationService.
    func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws {
        let rows = try modelContext.fetch(FetchDescriptor<TransactionModel>(
            predicate: #Predicate { $0.recurrenceRuleId == recurrenceRuleId && $0.timestamp >= cutoffDate }
        ))
        rows.forEach { modelContext.delete($0) }

        var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == recurrenceRuleId })
        ruleDesc.fetchLimit = 1
        if let rule = try modelContext.fetch(ruleDesc).first {
            // A conservative lower bound (not the exact prior occurrence) is enough: the
            // calculator only needs `since < nextDueOccurrence` to regenerate it correctly.
            rule.lastMaterializedDate = Calendar.current.date(byAdding: .day, value: -1, to: cutoffDate)
        }
        try modelContext.save()
    }

    func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws {
        guard !inputs.isEmpty else { return }
        for input in inputs {
            let model = TransactionModel(
                timestamp: input.timestamp,
                amount: input.amount,
                note: input.note,
                category: input.category,
                currencyCode: input.currencyCode,
                goalId: input.goalId,
                recurrenceRuleId: ruleId
            )
            if let pid = input.categoryPersistentId,
               let cat = modelContext.model(for: pid) as? CategoryModel {
                model.categoryModel = cat
            }
            modelContext.insert(model)
        }
        var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == ruleId })
        ruleDesc.fetchLimit = 1
        if let rule = try modelContext.fetch(ruleDesc).first {
            rule.lastMaterializedDate = newCursor
        }
        try modelContext.save()
    }
```

- [ ] **Step 6: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/TransactionActorRecurrenceTests"])
```
Expected: PASS (6/6).

- [ ] **Step 7: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift
git commit -m "feat: implement recurrence rule CRUD and atomic materialization on TransactionActor"
```

---

### Task 5: Mock repository + test factories

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/TransactionSnapshotFactory.swift`

**Interfaces:**
- Consumes: `ITransactionRepository` (Task 4), `RecurrenceRule`/`RecurrenceRuleSnapshot` (Tasks 2–3).
- Produces: `MockTransactionRepository` conforms to the full protocol; spies `addRecurrenceRuleCalls: [RecurrenceRuleInput]`, `materializeOccurrencesCalls: [(ruleId: UUID, inputs: [TransactionInput], newCursor: Date)]`, `fetchActiveRecurrenceRulesCallCount: Int`, `fetchActiveRecurrenceRulesDelayNanoseconds: UInt64`; `RecurrenceRuleSnapshot.test(...)` factory.

This task is test infrastructure with no independent logic to fail-first on — implement directly, then verify by building (the compiler enforces full protocol conformance).

- [ ] **Step 1: Extend `MockTransactionRepository`**

In `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift`, add stub storage/spies near the top:

```swift
    var stubbedRecurrenceRules: [RecurrenceRuleSnapshot] = []
    var addRecurrenceRuleCalls: [RecurrenceRuleInput] = []
    var updateRecurrenceRuleCalls: [(id: UUID, input: RecurrenceRuleInput)] = []
    var closeRecurrenceRuleCalls: [(id: UUID, endDate: Date)] = []
    var deleteOccurrencesCalls: [(recurrenceRuleId: UUID, cutoffDate: Date)] = []
    var materializeOccurrencesCalls: [(ruleId: UUID, inputs: [TransactionInput], newCursor: Date)] = []
    var fetchActiveRecurrenceRulesCallCount = 0
    var fetchActiveRecurrenceRulesDelayNanoseconds: UInt64 = 0
```

And the methods, e.g. after the Goals section:

```swift
    // MARK: Recurrence rules
    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws {
        if shouldThrow { throw MockError.forced }
        addRecurrenceRuleCalls.append(input)
    }

    func fetchActiveRecurrenceRules() async throws -> [RecurrenceRuleSnapshot] {
        fetchActiveRecurrenceRulesCallCount += 1
        if fetchActiveRecurrenceRulesDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: fetchActiveRecurrenceRulesDelayNanoseconds)
        }
        if shouldThrow { throw MockError.forced }
        return stubbedRecurrenceRules
    }

    func fetchRecurrenceRule(id: UUID) async throws -> RecurrenceRuleSnapshot? {
        if shouldThrow { throw MockError.forced }
        return stubbedRecurrenceRules.first { $0.id == id }
    }

    func updateRecurrenceRule(id: UUID, with input: RecurrenceRuleInput) async throws {
        if shouldThrow { throw MockError.forced }
        updateRecurrenceRuleCalls.append((id, input))
    }

    func closeRecurrenceRule(id: UUID, endDate: Date) async throws {
        if shouldThrow { throw MockError.forced }
        closeRecurrenceRuleCalls.append((id, endDate))
    }

    func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws {
        if shouldThrow { throw MockError.forced }
        deleteOccurrencesCalls.append((recurrenceRuleId, cutoffDate))
    }

    func materializeOccurrences(ruleId: UUID, inputs: [TransactionInput], newCursor: Date) async throws {
        if shouldThrow { throw MockError.forced }
        materializeOccurrencesCalls.append((ruleId, inputs, newCursor))
    }
```

- [ ] **Step 2: Add `RecurrenceRuleSnapshot.test(...)` factory**

In `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/TransactionSnapshotFactory.swift`, register the model in the shared schema:

```swift
private enum SnapshotTestSupport {
    static let container: ModelContainer = {
        let schema = Schema([TransactionModel.self, CategoryModel.self, GoalModel.self, RecurrenceRule.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}
```

Then add, after the `GoalSnapshot` extension:

```swift
extension RecurrenceRuleSnapshot {
    static func test(
        id: UUID = UUID(),
        frequency: RecurrenceFrequency = .monthly,
        interval: Int = 1,
        startDate: Date,
        endDate: Date? = nil,
        lastMaterializedDate: Date? = nil,
        amount: Decimal,
        note: String = "",
        category: String,
        currencyCode: String = "EUR",
        goalId: UUID? = nil
    ) -> RecurrenceRuleSnapshot {
        let context = ModelContext(SnapshotTestSupport.container)
        let model = RecurrenceRule(
            id: id, frequency: frequency, interval: interval, startDate: startDate,
            endDate: endDate, lastMaterializedDate: lastMaterializedDate,
            amount: amount, note: note, category: category, currencyCode: currencyCode, goalId: goalId
        )
        context.insert(model)
        return RecurrenceRuleSnapshot(model)
    }
}
```

- [ ] **Step 3: Build to confirm full protocol conformance and factory compile**

```
ToolSearch(query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests")
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: BUILD SUCCEEDED. If `MockTransactionRepository` is missing any protocol method, this fails with a clear "does not conform to protocol" error — fix and rebuild.

- [ ] **Step 4: Run the full test suite to confirm no regressions**

```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/TransactionSnapshotFactory.swift
git commit -m "test: extend MockTransactionRepository and snapshot factories for recurrence rules"
```

---

### Task 6: `RecurrenceMaterializationService`

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RecurrenceMaterializationService.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/RecurrenceMaterializationServiceTests.swift`

**Interfaces:**
- Consumes: `ITransactionRepository.fetchActiveRecurrenceRules/materializeOccurrences` (Task 4), `RecurrenceOccurrenceCalculator` (Task 1), `MockTransactionRepository` spies (Task 5).
- Produces: `actor RecurrenceMaterializationService { func materialize(using repo: any ITransactionRepository, today: Date = .now, calendar: Calendar = .current) async throws }`.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/RecurrenceMaterializationServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RecurrenceMaterializationServiceTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func materializesDueOccurrencesAndAdvancesCursor() async throws {
        let mock = MockTransactionRepository()
        mock.stubbedRecurrenceRules = [
            .test(startDate: date(2026, 1, 1), amount: -1200, category: "Rent")
        ]
        let service = RecurrenceMaterializationService()

        try await service.materialize(using: mock, today: date(2026, 3, 1))

        #expect(mock.materializeOccurrencesCalls.count == 1)
        let call = mock.materializeOccurrencesCalls[0]
        #expect(call.inputs.map(\.timestamp) == [date(2026, 1, 1), date(2026, 2, 1), date(2026, 3, 1)])
        #expect(call.inputs.allSatisfy { $0.recurrenceRuleId == call.ruleId })
        #expect(call.newCursor == date(2026, 3, 1))
    }

    @Test func skipsRuleWithNoDueOccurrencesYet() async throws {
        let mock = MockTransactionRepository()
        mock.stubbedRecurrenceRules = [
            .test(startDate: date(2026, 5, 1), amount: -1200, category: "Rent")
        ]
        let service = RecurrenceMaterializationService()

        try await service.materialize(using: mock, today: date(2026, 3, 1))

        #expect(mock.materializeOccurrencesCalls.isEmpty)
    }

    @Test func concurrentCallsOnlyFetchRulesOnce() async throws {
        let mock = MockTransactionRepository()
        mock.fetchActiveRecurrenceRulesDelayNanoseconds = 50_000_000 // 50ms — forces overlap
        mock.stubbedRecurrenceRules = [
            .test(startDate: date(2026, 1, 1), amount: -1200, category: "Rent")
        ]
        let service = RecurrenceMaterializationService()

        async let first: Void = service.materialize(using: mock, today: date(2026, 3, 1))
        async let second: Void = service.materialize(using: mock, today: date(2026, 3, 1))
        _ = try await (first, second)

        #expect(mock.fetchActiveRecurrenceRulesCallCount == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/RecurrenceMaterializationServiceTests"])
```
Expected: build FAILS — `RecurrenceMaterializationService` doesn't exist yet.

- [ ] **Step 3: Implement the service**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RecurrenceMaterializationService.swift`:

```swift
import Foundation

/// Materializes due `RecurrenceRule` occurrences into real `TransactionModel` rows.
/// Launch/foreground-triggered only (see MainTabView) — no background execution,
/// matching how DailyForecastCache and the daily log reminder already work.
actor RecurrenceMaterializationService {
    private var inFlight: Task<Void, Error>?

    /// Safe to call from multiple launch/foreground hooks in close succession: if a pass is
    /// already running, this call awaits it instead of starting a second *overlapping* pass
    /// that could read the same lastMaterializedDate cursor and double-insert. This guard is
    /// only about overlap — it does NOT collapse into a once-per-session no-op. Two calls that
    /// don't overlap (e.g. launch, then a foreground resume minutes later) each run a full,
    /// necessary pass so catch-up keeps working; don't "optimize" this into a run-once guard.
    func materialize(using repo: any ITransactionRepository, today: Date = .now, calendar: Calendar = .current) async throws {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task {
            try await Self.runMaterialization(using: repo, today: today, calendar: calendar)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    private static func runMaterialization(using repo: any ITransactionRepository, today: Date, calendar: Calendar) async throws {
        let rules = try await repo.fetchActiveRecurrenceRules()
        for rule in rules {
            let dates = RecurrenceOccurrenceCalculator.occurrenceDates(
                frequency: rule.frequency,
                interval: rule.interval,
                startDate: rule.startDate,
                ruleEndDate: rule.endDate,
                since: rule.lastMaterializedDate,
                through: today,
                calendar: calendar
            )
            guard let newCursor = dates.last else { continue }
            let inputs = dates.map { occurrenceDate in
                TransactionInput(
                    timestamp: occurrenceDate,
                    amount: rule.amount,
                    note: rule.note,
                    category: rule.category,
                    currencyCode: rule.currencyCode,
                    goalId: rule.goalId,
                    categoryPersistentId: rule.categoryId,
                    recurrenceRuleId: rule.id
                )
            }
            try await repo.materializeOccurrences(ruleId: rule.id, inputs: inputs, newCursor: newCursor)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/RecurrenceMaterializationServiceTests"])
```
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RecurrenceMaterializationService.swift PersonalFinanceTrakerTests/Utilities/RecurrenceMaterializationServiceTests.swift
git commit -m "feat: add RecurrenceMaterializationService with re-entrancy guard"
```

---

### Task 7: Wire materialization into `MainTabView`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift`

**Interfaces:**
- Consumes: `RecurrenceMaterializationService.materialize(using:)` (Task 6), existing `repo: TransactionActor`, `dataChanged: DataChangedSignal`.

No new automated test — this is two call sites of already-tested logic wired into existing, untested SwiftUI glue (`MainTabView` has no test target). Verify by building and a manual Simulator check after Task 11, when there's a full flow to exercise. (See Task 11's manual verification step.)

- [ ] **Step 1: Add the service and call it on launch**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift`, add a property:

```swift
    private let repo: TransactionActor
    private let materializationService = RecurrenceMaterializationService()
```

Update the `.task` block:

```swift
        .task {
            viewModel.onDataChanged = { dataChanged.bump() }
            compassViewModel.onDataChanged = { dataChanged.bump() }
            viewModel.load()  // ponytail: pre-warm Activity while user is on Home; isLoaded guard makes repeat a no-op
            try? await materializationService.materialize(using: repo)
            dataChanged.bump()
        }
```

- [ ] **Step 2: Also call it on foreground resume**

Update the `scenePhase == .active` branch:

```swift
            if phase == .active {
                // Data may have changed outside the UI (App Intent quick-add)
                dashboardViewModel.reload()
                viewModel.reload()
                Task {
                    try? await materializationService.materialize(using: repo)
                    dataChanged.bump()
                }
            }
```

- [ ] **Step 3: Build to confirm it compiles**

```
ToolSearch(query: "select:mcp__xcode__BuildProject")
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift
git commit -m "feat: materialize due recurring transactions on launch and foreground resume"
```

---

### Task 8: `EditAddTransactionViewModel` — create-time Repeat state

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift`

**Interfaces:**
- Consumes: `RecurrenceFrequency` (Task 1), `RecurrenceRuleInput`, `TransactionInput.recurrenceRuleId` (Task 3), `ITransactionRepository.addRecurrenceRule/materializeOccurrences` (Task 4).
- Produces: `EditAddTransactionViewModel.isRecurring: Bool`, `.recurrenceFrequency: RecurrenceFrequency`, `.recurrenceInterval: Int`; `func buildRecurrenceRuleInput() -> RecurrenceRuleInput?`; `func saveRecurringTransaction() async throws`.

- [ ] **Step 1: Write the failing tests**

Append to `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift`:

```swift
// MARK: - Recurrence (create-time)

extension EditAddTransactionViewModelTests {
    @Test @MainActor func buildRecurrenceRuleInputIsNilWhenNotRecurring() async throws {
        let vm = makeVM()
        vm.transactionName = "Rent"
        vm.amount = 1200
        vm.selectedCategory = expenseCat()
        vm.isRecurring = false
        #expect(vm.buildRecurrenceRuleInput() == nil)
    }

    @Test @MainActor func buildRecurrenceRuleInputIsNilForTransfers() async throws {
        let vm = makeVM()
        vm.transactionName = "To savings"
        vm.amount = 200
        vm.transactionType = .transfer
        vm.selectedGoal = .test(name: "Vacation", targetAmount: 1000)
        vm.isRecurring = true
        #expect(vm.buildRecurrenceRuleInput() == nil)
    }

    @Test @MainActor func buildRecurrenceRuleInputMatchesFormWhenRecurring() async throws {
        let vm = makeVM()
        vm.transactionName = "Rent"
        vm.amount = 1200
        vm.transactionType = .expense
        vm.selectedCategory = expenseCat()
        vm.isRecurring = true
        vm.recurrenceFrequency = .monthly
        vm.recurrenceInterval = 1

        let ruleInput = try #require(vm.buildRecurrenceRuleInput())
        #expect(ruleInput.frequency == .monthly)
        #expect(ruleInput.interval == 1)
        #expect(ruleInput.amount == -1200)
        #expect(ruleInput.category == "Food")
    }

    @Test @MainActor func saveRecurringTransactionCreatesRuleAndMaterializesFirstOccurrence() async throws {
        let mock = MockTransactionRepository()
        let vm = EditAddTransactionViewModel(repo: mock)
        vm.transactionName = "Rent"
        vm.amount = 1200
        vm.selectedCategory = expenseCat()
        vm.isRecurring = true
        vm.recurrenceFrequency = .monthly

        try await vm.saveRecurringTransaction()

        #expect(mock.addRecurrenceRuleCalls.count == 1)
        #expect(mock.materializeOccurrencesCalls.count == 1)
        let call = mock.materializeOccurrencesCalls[0]
        #expect(call.ruleId == mock.addRecurrenceRuleCalls[0].id)
        #expect(call.inputs.count == 1)
        #expect(call.inputs[0].timestamp == mock.addRecurrenceRuleCalls[0].startDate)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/EditAddTransactionViewModelTests"])
```
Expected: build FAILS — `isRecurring`/`recurrenceFrequency`/`recurrenceInterval`/`buildRecurrenceRuleInput`/`saveRecurringTransaction` don't exist yet.

- [ ] **Step 3: Implement**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift`, add properties near the other `@Observable` state:

```swift
    var isRecurring: Bool = false
    var recurrenceFrequency: RecurrenceFrequency = .monthly
    var recurrenceInterval: Int = 1
```

Add, near `buildInput()`:

```swift
    /// nil when not recurring, editing an existing transaction, or the type is Transfer
    /// (goal-linked recurrence is deferred — see docs/superpowers/specs/2026-08-02-recurring-transactions-design.md).
    func buildRecurrenceRuleInput() -> RecurrenceRuleInput? {
        guard isRecurring, editingItem == nil, transactionType != .transfer,
              let input = buildInput() else { return nil }
        return RecurrenceRuleInput(
            frequency: recurrenceFrequency,
            interval: recurrenceInterval,
            startDate: input.timestamp,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            categoryPersistentId: input.categoryPersistentId
        )
    }

    /// Creates the rule and immediately materializes its first occurrence, so the new
    /// transaction is visible right away instead of waiting for the next launch/foreground pass.
    func saveRecurringTransaction() async throws {
        guard let ruleInput = buildRecurrenceRuleInput() else { return }
        try await repo.addRecurrenceRule(ruleInput)
        let firstOccurrence = TransactionInput(
            timestamp: ruleInput.startDate,
            amount: ruleInput.amount,
            note: ruleInput.note,
            category: ruleInput.category,
            currencyCode: ruleInput.currencyCode,
            goalId: ruleInput.goalId,
            categoryPersistentId: ruleInput.categoryPersistentId,
            recurrenceRuleId: ruleInput.id
        )
        try await repo.materializeOccurrences(ruleId: ruleInput.id, inputs: [firstOccurrence], newCursor: ruleInput.startDate)
    }
```

Also update `resetForm()` to reset the new fields:

```swift
    func resetForm() {
        transactionName = ""
        amount = 0
        transactionType = .expense
        currencyCode = UserDefaults.standard.string(forKey: "app_base_currency") ?? "EUR"
        date = Date()
        selectedCategory = nil
        selectedGoal = nil
        isRecurring = false
        recurrenceFrequency = .monthly
        recurrenceInterval = 1
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/EditAddTransactionViewModelTests"])
```
Expected: PASS (all, including the 4 new tests).

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift
git commit -m "feat: add Repeat toggle state and rule creation to EditAddTransactionViewModel"
```

---

### Task 9: Repeat toggle UI in `TransactionFormView`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/TransactionFormView.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`

**Interfaces:**
- Consumes: `EditAddTransactionViewModel.isRecurring/.recurrenceFrequency/.recurrenceInterval` (Task 8), `EditAddTransactionViewModel.saveRecurringTransaction()` (Task 8).

No new automated test — pure SwiftUI layout consuming already-tested view-model state. Verify with a build and, once Task 11 completes the flow, a manual Simulator check.

- [ ] **Step 1: Add the Repeat section**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/TransactionFormView.swift`, insert after the Date section (before the category/goal `if`):

```swift
                if viewModel.editingItem == nil && viewModel.transactionType != .transfer {
                    Section {
                        Toggle("Repeat", isOn: $viewModel.isRecurring)
                        if viewModel.isRecurring {
                            Picker("Frequency", selection: $viewModel.recurrenceFrequency) {
                                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                                    Text(freq.label).tag(freq)
                                }
                            }
                            .onChange(of: viewModel.recurrenceFrequency) { _, newFrequency in
                                viewModel.recurrenceInterval = min(viewModel.recurrenceInterval, newFrequency.maxInterval)
                            }
                            Stepper(
                                "Every \(viewModel.recurrenceInterval) \(viewModel.recurrenceFrequency.unitLabel(for: viewModel.recurrenceInterval))",
                                value: $viewModel.recurrenceInterval,
                                in: 1...viewModel.recurrenceFrequency.maxInterval
                            )
                        }
                    }
                    .appFormSectionBackground()
                }
```

- [ ] **Step 2: Reset `isRecurring` when switching to Transfer**

In the same file, the existing `Type` picker's `onChange` already resets `selectedCategory`/`selectedGoal`; extend it:

```swift
                    .onChange(of: viewModel.transactionType) { _, newType in
                        viewModel.selectedCategory = nil
                        viewModel.selectedGoal = nil
                        if newType == .transfer { viewModel.isRecurring = false }
                    }
```

- [ ] **Step 3: Wire Save to create the rule when recurring**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`, update `saveTransaction()`'s add branch:

```swift
    private func saveTransaction() {
        Task {
            if let existing = viewModel.editingItem {
                if let input = viewModel.buildInput() {
                    try? await viewModel.repo.update(id: existing.id, with: input)
                }
            } else if viewModel.isRecurring {
                try? await viewModel.saveRecurringTransaction()
            } else if let input = viewModel.buildInput() {
                try? await viewModel.repo.add(input)
            }
            dataChanged.bump()
            dismiss()
        }
    }
```

(The `existing.editingItem != nil` branch is intentionally left simple here — Task 11 replaces it with the "This transaction"/"This and future" prompt for rows that carry a `recurrenceRuleId`.)

- [ ] **Step 4: Build to confirm it compiles**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/TransactionFormView.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift
git commit -m "feat: add Repeat toggle and frequency picker to the Add Transaction form"
```

---

### Task 10: "This and future" edit support in the view model

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift`

**Interfaces:**
- Consumes: `ITransactionRepository.fetchRecurrenceRule` (Task 4).
- Produces: `func buildRecurrenceRuleInput(preserving rule: RecurrenceRuleSnapshot) -> RecurrenceRuleInput?` — updates only the editable template fields (amount/note/category/currency/goal) and keeps `frequency`/`interval`/`startDate`/`id` from the existing rule, since v1's edit UI never shows those fields and changing `startDate` would shift every future occurrence date.

- [ ] **Step 1: Write the failing test**

Append to `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift`:

```swift
extension EditAddTransactionViewModelTests {
    @Test @MainActor func buildRecurrenceRuleInputPreservingKeepsCadenceAndUpdatesTemplate() async throws {
        let originalStart = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01
        let existingRule = RecurrenceRuleSnapshot.test(
            frequency: .yearly, interval: 2, startDate: originalStart, amount: -1200, category: "Housing"
        )
        let vm = makeVM()
        vm.transactionName = "Rent (increased)"
        vm.amount = 1500
        vm.selectedCategory = expenseCat()

        let result = try #require(vm.buildRecurrenceRuleInput(preserving: existingRule))
        #expect(result.id == existingRule.id)
        #expect(result.frequency == .yearly)
        #expect(result.interval == 2)
        #expect(result.startDate == originalStart)
        #expect(result.amount == -1500)
        #expect(result.note == "Rent (increased)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/EditAddTransactionViewModelTests"])
```
Expected: build FAILS — `buildRecurrenceRuleInput(preserving:)` doesn't exist yet.

- [ ] **Step 3: Implement**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift`, add next to `buildRecurrenceRuleInput()`:

```swift
    /// Used for "this and future" edits: keeps the rule's cadence (frequency/interval/startDate)
    /// untouched — v1's edit form never shows those fields, and changing startDate would shift
    /// every future occurrence date — and applies only the template fields visible in the form.
    func buildRecurrenceRuleInput(preserving rule: RecurrenceRuleSnapshot) -> RecurrenceRuleInput? {
        guard let input = buildInput() else { return nil }
        return RecurrenceRuleInput(
            id: rule.id,
            frequency: rule.frequency,
            interval: rule.interval,
            startDate: rule.startDate,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId,
            categoryPersistentId: input.categoryPersistentId
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/EditAddTransactionViewModelTests"])
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift
git commit -m "feat: preserve recurrence cadence when building a this-and-future rule update"
```

---

### Task 11: Edit/delete scope prompt in `EditAddTransactionView`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`

**Interfaces:**
- Consumes: `TransactionSnapshot.recurrenceRuleId` (Task 3), `ITransactionRepository.updateRecurrenceRule/closeRecurrenceRule/deleteOccurrences/fetchRecurrenceRule` (Task 4), `EditAddTransactionViewModel.buildRecurrenceRuleInput(preserving:)` (Task 10), `RecurrenceMaterializationService.materialize(using:)` (Task 6) — needed so a "this and future" save regenerates the just-edited row immediately instead of leaving it missing until next launch/foreground.

No new automated test — this is SwiftUI orchestration whose branches are each individually covered by Task 4's actor tests and Task 10's view-model test. Verify with a build, then a manual Simulator walkthrough (this is the first point where the full feature is wired end-to-end).

- [ ] **Step 1: Add scope state and the confirmation dialog**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`:

```swift
private enum PendingRecurrenceAction {
    case save(TransactionInput)
    case delete
}

private enum RecurrenceEditScope {
    case thisOnly
    case thisAndFuture
}
```

```swift
struct EditAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataChangedSignal.self) private var dataChanged
    @State private var viewModel: EditAddTransactionViewModel
    @State private var pendingRecurrenceAction: PendingRecurrenceAction?
    private let materializationService = RecurrenceMaterializationService()
```

In `body`, add the dialog alongside the existing `.toolbar`/`.onAppear`:

```swift
        .confirmationDialog(
            "This is part of a recurring series",
            isPresented: Binding(
                get: { pendingRecurrenceAction != nil },
                set: { if !$0 { pendingRecurrenceAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("This transaction") { applyPendingAction(scope: .thisOnly) }
            Button("This and future", role: .destructive) { applyPendingAction(scope: .thisAndFuture) }
            Button("Cancel", role: .cancel) { pendingRecurrenceAction = nil }
        }
```

- [ ] **Step 2: Route save/delete through the scope prompt when the row is recurring**

Replace `saveTransaction()` and `deleteTransaction()`:

```swift
    private func saveTransaction() {
        guard let existing = viewModel.editingItem else {
            Task {
                if viewModel.isRecurring {
                    try? await viewModel.saveRecurringTransaction()
                } else if let input = viewModel.buildInput() {
                    try? await viewModel.repo.add(input)
                }
                dataChanged.bump()
                dismiss()
            }
            return
        }
        guard let input = viewModel.buildInput() else { return }
        if existing.recurrenceRuleId != nil {
            pendingRecurrenceAction = .save(input)
        } else {
            Task {
                try? await viewModel.repo.update(id: existing.id, with: input)
                dataChanged.bump()
                dismiss()
            }
        }
    }

    private func deleteTransaction() {
        guard let existing = viewModel.editingItem else { return }
        if existing.recurrenceRuleId != nil {
            pendingRecurrenceAction = .delete
        } else {
            Task {
                try? await viewModel.repo.delete(id: existing.id)
                dataChanged.bump()
                dismiss()
            }
        }
    }

    private func applyPendingAction(scope: RecurrenceEditScope) {
        guard let action = pendingRecurrenceAction,
              let existing = viewModel.editingItem,
              let ruleId = existing.recurrenceRuleId else {
            pendingRecurrenceAction = nil
            return
        }
        pendingRecurrenceAction = nil
        Task {
            switch (action, scope) {
            case (.save(let input), .thisOnly):
                try? await viewModel.repo.update(id: existing.id, with: input)

            case (.save, .thisAndFuture):
                if let rule = try? await viewModel.repo.fetchRecurrenceRule(id: ruleId),
                   let ruleInput = viewModel.buildRecurrenceRuleInput(preserving: rule) {
                    try? await viewModel.repo.updateRecurrenceRule(id: ruleId, with: ruleInput)
                    try? await viewModel.repo.deleteOccurrences(recurrenceRuleId: ruleId, from: existing.timestamp)
                    // deleteOccurrences just removed the row being edited (its timestamp >= cutoff) along
                    // with any later ones. Re-materialize immediately — dismissing this sheet is neither a
                    // launch nor a foreground transition, so without this call the edited transaction would
                    // stay missing from Activity until the user backgrounds/relaunches the app.
                    try? await materializationService.materialize(using: viewModel.repo)
                }

            case (.delete, .thisOnly):
                try? await viewModel.repo.delete(id: existing.id)

            case (.delete, .thisAndFuture):
                let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: existing.timestamp) ?? existing.timestamp
                try? await viewModel.repo.closeRecurrenceRule(id: ruleId, endDate: dayBefore)
                try? await viewModel.repo.deleteOccurrences(recurrenceRuleId: ruleId, from: existing.timestamp)
            }
            dataChanged.bump()
            dismiss()
        }
    }
```

- [ ] **Step 3: Build to confirm it compiles**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full test suite**

```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```
Expected: PASS — no regressions across the whole feature.

- [ ] **Step 5: Manual verification in the Simulator**

Launch the app (Xcode MCP run), then:
1. Add a new expense, toggle Repeat on, frequency Monthly, save — confirm it appears immediately in Activity.
2. Force-quit and relaunch (or background/foreground) with the system clock advanced a month (or use a rule dated in the past) — confirm the next occurrence appears without manual entry.
3. Edit that recurring transaction, change the amount, choose "This and future" — confirm this occurrence updates and a re-launch regenerates future ones with the new amount, while any older occurrence keeps the original amount.
4. Delete a recurring transaction with "This and future" — confirm no further occurrences appear after a relaunch, and past occurrences remain untouched.

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift
git commit -m "feat: add this-transaction vs this-and-future prompt for recurring transaction edits/deletes"
```

---

## Deferred (not in this plan, per spec)

- Goal-linked auto-contribution behavior (the `goalId` field exists but nothing acts on goal completion/overshoot).
- Wiring into `ReminderService` for "bill due" notifications.
- Insights card for subscription spend.
- Feeding `RecurrenceRule` projections into `SpendingForecastService`.
- A dedicated "Recurring" management/list screen.
- Per-instance exception overrides (EventKit-style).
