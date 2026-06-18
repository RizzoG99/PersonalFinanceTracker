# Health Score V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Health Score with persisted history, per-component tips and plain-language explanations, a detail sheet, and a subscription opt-out toggle.

**Architecture:** A new `HealthScoreSnapshot` SwiftData model stores one score per day; `FinancialHealthService` is extended to emit explanation strings and actionable tips on each `ScoreComponent`; a new `HealthScoreDetailView` sheet surfaces history, expanded components, and the opt-out toggle; `HealthScoreCard` gains a sparkline and becomes tappable.

**Tech Stack:** SwiftUI, SwiftData, Swift Charts, Swift Testing (`@Test` / `#expect`), `@Observable` ViewModel pattern.

## Global Constraints

- iOS 26+, Swift 6
- Swift Testing framework only — import with `import Testing`, use `@Test` and `#expect`. No XCTest.
- `@testable import PersonalFinanceTraker` in all test files.
- `@Observable @MainActor` on ViewModels — no `@Published`, no `ObservableObject`.
- SwiftData for persistence — no CoreData.
- No migration needed for schema changes (app not on App Store — reinstall clears data).
- EUR currency is hardcoded in display strings (use `€` symbol).
- Directory name typo is intentional: `PersonalFinanceTraker` (one 'c').
- No comments unless the WHY is non-obvious.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `PersonalFinanceTraker/PersonalFinanceTraker/Models/HealthScoreSnapshot.swift` | SwiftData model for persisted score snapshot |
| Create | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift` | Detail sheet: history chart + expanded components + toggle |
| Create | `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/Insights/FinancialHealthServiceTests.swift` | Tests for tips, explanations, opt-out redistribution |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/CompassDataModels.swift` | Add `explanation: String` and `tip: String?` to `ScoreComponent` |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift` | Add `saveSnapshot(_:)` and `fetchSnapshots(limit:)` to protocol + implementation |
| Modify | `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift` | Implement new snapshot protocol methods |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/FinancialHealthService.swift` | Add `ignoreSubscriptions` param, populate `explanation` and `tip` |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift` | Add `scoreSnapshots`, `ignoreSubscriptions`, snapshot save/fetch |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift` | Add sparkline above gauge, make card tappable |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift` | Add `snapshots` param, sheet state, present `HealthScoreDetailView` |
| Modify | `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift` | Register `HealthScoreSnapshot` in SwiftData schema |

---

### Task 1: `HealthScoreSnapshot` model + schema registration

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/HealthScoreSnapshot.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`

**Interfaces:**
- Produces: `HealthScoreSnapshot` — used in Tasks 2, 4, 5, 6

- [ ] **Step 1: Create the SwiftData model**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Models/HealthScoreSnapshot.swift`:

```swift
import SwiftData
import Foundation

@Model
final class HealthScoreSnapshot {
    var timestamp: Date
    var score: Int
    var savingsScore: Int
    var stabilityScore: Int
    var adherenceScore: Int
    var subscriptionScore: Int

    init(timestamp: Date, score: Int, savingsScore: Int, stabilityScore: Int,
         adherenceScore: Int, subscriptionScore: Int) {
        self.timestamp = timestamp
        self.score = score
        self.savingsScore = savingsScore
        self.stabilityScore = stabilityScore
        self.adherenceScore = adherenceScore
        self.subscriptionScore = subscriptionScore
    }
}
```

- [ ] **Step 2: Register in schema**

In `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`, update the schema array:

```swift
let schema = Schema([
    TransactionModel.self,
    CategoryModel.self,
    CreditCardModel.self,
    GoalModel.self,
    HealthScoreSnapshot.self,   // add this line
])
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/HealthScoreSnapshot.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift
git commit -m "Add HealthScoreSnapshot SwiftData model and register in schema"
```

---

### Task 2: Repository snapshot methods

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/Insights/FinancialHealthServiceTests.swift` (skeleton only — populated in Task 3)

**Interfaces:**
- Consumes: `HealthScoreSnapshot` from Task 1
- Produces:
  - `ITransactionRepository.saveSnapshot(_ snapshot: HealthScoreSnapshot) throws`
  - `ITransactionRepository.fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot]`

- [ ] **Step 1: Add methods to the protocol**

In `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift`, add to `ITransactionRepository` after the goal management block:

```swift
    // Snapshot management
    func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws
    func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot]
```

- [ ] **Step 2: Implement in `TransactionRepository`**

Add the following two methods to `TransactionRepository` (before the closing brace):

```swift
    func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws {
        context.insert(snapshot)
        try context.save()
    }

    func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot] {
        var desc = FetchDescriptor<HealthScoreSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return try context.fetch(desc)
    }
```

- [ ] **Step 3: Update `MockTransactionRepository`**

In `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift`, add:

```swift
    var snapshots: [HealthScoreSnapshot] = []
    var saveSnapshotCalledCount = 0

    func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws {
        saveSnapshotCalledCount += 1
        if shouldFail { throw NSError(domain: "MockError", code: 5, userInfo: nil) }
        snapshots.append(snapshot)
    }

    func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot] {
        if shouldFail { throw NSError(domain: "MockError", code: 6, userInfo: nil) }
        return Array(snapshots.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }
```

- [ ] **Step 4: Create test file skeleton**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/Insights/FinancialHealthServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite("FinancialHealthService")
struct FinancialHealthServiceTests {}
```

- [ ] **Step 5: Build to verify no compile errors**

```bash
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift \
        PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift \
        PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/Insights/FinancialHealthServiceTests.swift
git commit -m "Add snapshot repository methods and update mock"
```

---

### Task 3: Extend `ScoreComponent` + rewrite `FinancialHealthService`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/CompassDataModels.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/FinancialHealthService.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/Insights/FinancialHealthServiceTests.swift`

**Interfaces:**
- Produces:
  - `ScoreComponent.explanation: String`
  - `ScoreComponent.tip: String?`
  - `FinancialHealthService.compute(transactions:expenseTransactions:budgetedCategories:ignoreSubscriptions:) -> HealthScore`

- [ ] **Step 1: Write the failing tests**

Replace the skeleton in `FinancialHealthServiceTests.swift` with:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite("FinancialHealthService")
struct FinancialHealthServiceTests {

    private func makeService() -> FinancialHealthService {
        FinancialHealthService(currencyService: CurrencyService())
    }

    private func makeIncome(amount: Decimal, monthsAgo: Int = 0) -> TransactionModel {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return TransactionModel(timestamp: date, amount: amount, note: "", category: "Salary", currencyCode: "EUR", goalId: nil)
    }

    private func makeExpense(amount: Decimal, category: String = "Groceries", monthsAgo: Int = 0) -> TransactionModel {
        let date = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        return TransactionModel(timestamp: date, amount: -abs(amount), note: "", category: category, currencyCode: "EUR", goalId: nil)
    }

    @Test("tip is nil when savings score is maxed (≥20% savings rate)")
    func savingsTipNilWhenMaxed() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 700, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        let savings = result.components.first { $0.name == "Savings rate" }!
        #expect(savings.tip == nil)
    }

    @Test("tip is non-nil when savings score is below max")
    func savingsTipPresentWhenBelowMax() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 900, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        let savings = result.components.first { $0.name == "Savings rate" }!
        #expect(savings.tip != nil)
    }

    @Test("explanation is non-empty for all components")
    func allExplanationsNonEmpty() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 800, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: false
        )
        for component in result.components {
            #expect(!component.explanation.isEmpty)
        }
    }

    @Test("ignoreSubscriptions produces 3 components summing to ≤100")
    func optOutGivesThreeComponents() {
        let service = makeService()
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 800, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: true
        )
        #expect(result.components.count == 3)
        #expect(result.score <= 100)
        #expect(result.score >= 0)
    }

    @Test("ignoreSubscriptions maxes at 100 when all components are perfect")
    func optOutMaxScore() {
        let service = makeService()
        // Perfect savings (>20%), stable spending, no budget categories
        let income = (0..<6).map { makeIncome(amount: 1000, monthsAgo: $0) }
        let expenses = (0..<6).map { makeExpense(amount: 700, monthsAgo: $0) }
        let result = service.compute(
            transactions: income + expenses,
            expenseTransactions: expenses,
            budgetedCategories: [],
            ignoreSubscriptions: true
        )
        #expect(result.components.map(\.max).reduce(0, +) == 100)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PersonalFinanceTrakerTests/FinancialHealthServiceTests \
  2>&1 | grep -E "error:|Test.*failed|Build succeeded|Test.*passed"
```

Expected: compile error because `ScoreComponent` is missing `explanation` and `tip`, and `compute` is missing `ignoreSubscriptions`.

- [ ] **Step 3: Extend `ScoreComponent` in `CompassDataModels.swift`**

Replace the existing `ScoreComponent` struct:

```swift
struct ScoreComponent: Identifiable {
    let id = UUID()
    let name: String
    let score: Int
    let max: Int
    let explanation: String
    let tip: String?
}
```

- [ ] **Step 4: Rewrite `FinancialHealthService.swift`**

Replace the entire file content:

```swift
import Foundation

struct FinancialHealthService {
    let currencyService: CurrencyService

    func compute(
        transactions: [TransactionModel],
        expenseTransactions: [TransactionModel],
        budgetedCategories: [CategoryModel],
        ignoreSubscriptions: Bool = false
    ) -> HealthScore {
        let calendar = Calendar.current
        let now = Date.now
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
        let recent = transactions.filter { $0.timestamp >= sixMonthsAgo }
        let recentExpenses = expenseTransactions.filter { $0.timestamp >= sixMonthsAgo }

        // 1. Savings rate (target: 20% → full score)
        let income = recent.filter { $0.amount > 0 }.reduce(Decimal(0)) {
            $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode)
        }
        let expenses = sumExpenses(recentExpenses)
        let savingsRate = income > 0
            ? Double(truncating: ((income - expenses) / income) as NSDecimalNumber)
            : 0
        let rawSavingsScore = max(0, min(25, Int((savingsRate / 0.20) * 25)))

        // 2. Spending stability via coefficient of variation
        let monthlyExpenses: [Double] = (0..<6).map { offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            let total = expenseTransactions
                .filter { $0.timestamp >= start && $0.timestamp < end }
                .reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) }
            return Double(truncating: abs(total) as NSDecimalNumber)
        }
        let mean = monthlyExpenses.reduce(0, +) / 6
        let variance = mean > 0
            ? monthlyExpenses.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 6
            : 0
        let cov = mean > 0 ? variance.squareRoot() / mean : 0
        let rawStabilityScore = max(0, min(25, Int((1.0 - cov / 0.5) * 25)))

        // 3. Budget adherence (current month only)
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let thisMonthExpenses = expenseTransactions.filter { $0.timestamp >= startOfMonth }
        let rawAdherenceScore: Int
        let adheringCount: Int
        if budgetedCategories.isEmpty {
            rawAdherenceScore = 15
            adheringCount = 0
        } else {
            let adhering = budgetedCategories.filter { cat in
                let spent = sumExpenses(thisMonthExpenses.filter {
                    $0.category.localizedCaseInsensitiveContains(cat.name)
                })
                return spent <= (cat.monthlyBudget ?? 0)
            }
            adheringCount = adhering.count
            rawAdherenceScore = Int(Double(adheringCount) / Double(budgetedCategories.count) * 25)
        }

        // 4. Subscription control (above 15% of expenses = 0 pts)
        let subscriptionExpenses = sumExpenses(recentExpenses.filter {
            $0.category.localizedCaseInsensitiveContains("subscri") ||
            $0.category.localizedCaseInsensitiveContains("stream")
        })
        let subRatio = expenses > 0
            ? Double(truncating: (subscriptionExpenses / expenses) as NSDecimalNumber)
            : 0
        let rawSubscriptionScore = max(0, min(25, Int((1.0 - subRatio / 0.15) * 25)))

        // Build components — redistribute subscription pts when opted out
        let components: [ScoreComponent]
        let total: Int

        if ignoreSubscriptions {
            // 100 pts split across 3 components: savings=34, stability=33, adherence=33
            let savingsScore  = min(34, Int(Double(rawSavingsScore)   / 25.0 * 34.0))
            let stabilityScore = min(33, Int(Double(rawStabilityScore) / 25.0 * 33.0))
            let adherenceScore = min(33, Int(Double(rawAdherenceScore) / 25.0 * 33.0))
            total = savingsScore + stabilityScore + adherenceScore
            components = [
                ScoreComponent(
                    name: "Savings rate", score: savingsScore, max: 34,
                    explanation: savingsExplanation(rate: savingsRate),
                    tip: savingsScore < 34 ? savingsTip(rate: savingsRate, income: income) : nil
                ),
                ScoreComponent(
                    name: "Stability", score: stabilityScore, max: 33,
                    explanation: stabilityExplanation(cov: cov),
                    tip: stabilityScore < 33 ? stabilityTip() : nil
                ),
                ScoreComponent(
                    name: "Budget", score: adherenceScore, max: 33,
                    explanation: adherenceExplanation(adhering: adheringCount, total: budgetedCategories.count),
                    tip: adherenceScore < 33 ? adherenceTip(adhering: adheringCount, total: budgetedCategories.count) : nil
                ),
            ]
        } else {
            total = rawSavingsScore + rawStabilityScore + rawAdherenceScore + rawSubscriptionScore
            components = [
                ScoreComponent(
                    name: "Savings rate", score: rawSavingsScore, max: 25,
                    explanation: savingsExplanation(rate: savingsRate),
                    tip: rawSavingsScore < 25 ? savingsTip(rate: savingsRate, income: income) : nil
                ),
                ScoreComponent(
                    name: "Stability", score: rawStabilityScore, max: 25,
                    explanation: stabilityExplanation(cov: cov),
                    tip: rawStabilityScore < 25 ? stabilityTip() : nil
                ),
                ScoreComponent(
                    name: "Budget", score: rawAdherenceScore, max: 25,
                    explanation: adherenceExplanation(adhering: adheringCount, total: budgetedCategories.count),
                    tip: rawAdherenceScore < 25 ? adherenceTip(adhering: adheringCount, total: budgetedCategories.count) : nil
                ),
                ScoreComponent(
                    name: "Subscriptions", score: rawSubscriptionScore, max: 25,
                    explanation: subscriptionExplanation(ratio: subRatio),
                    tip: rawSubscriptionScore < 25 ? subscriptionTip() : nil
                ),
            ]
        }

        let label: String
        switch total {
        case 80...100: label = "Excellent financial habits"
        case 60...79:  label = "Solid with room to grow"
        case 40...59:  label = "Making progress"
        default:       label = "Needs attention"
        }

        return HealthScore(score: total, label: label, components: components)
    }

    // MARK: - Explanation helpers

    private func savingsExplanation(rate: Double) -> String {
        "You saved \(Int(rate * 100))% of income over the last 6 months."
    }

    private func savingsTip(rate: Double, income: Decimal) -> String {
        let needed = max(Decimal(0), Decimal(0.20 - rate)) * income / 6
        let rounded = Int(truncating: needed as NSDecimalNumber)
        return "Save €\(rounded) more per month to reach the 20% target."
    }

    private func stabilityExplanation(cov: Double) -> String {
        "Your monthly spending varies by \(Int(cov * 100))%."
    }

    private func stabilityTip() -> String {
        "Keep variation under 25% to earn full points."
    }

    private func adherenceExplanation(adhering: Int, total: Int) -> String {
        guard total > 0 else { return "No budgeted categories set." }
        return "\(adhering) of \(total) budgeted categories are within limit this month."
    }

    private func adherenceTip(adhering: Int, total: Int) -> String {
        guard total > 0 else { return "Set monthly budgets in Profile to unlock this score." }
        let over = total - adhering
        return "Bring \(over) over-budget \(over == 1 ? "category" : "categories") within limit."
    }

    private func subscriptionExplanation(ratio: Double) -> String {
        "Subscriptions are \(Int(ratio * 100))% of expenses over the last 6 months."
    }

    private func subscriptionTip() -> String {
        "Keep subscriptions under 15% of expenses to earn full points."
    }

    private func sumExpenses(_ items: [TransactionModel]) -> Decimal {
        abs(items.reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) })
    }
}
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PersonalFinanceTrakerTests/FinancialHealthServiceTests \
  2>&1 | grep -E "error:|Test.*failed|Build succeeded|passed"
```

Expected: all 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Models/CompassDataModels.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/Utilities/FinancialHealthService.swift \
        PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/Insights/FinancialHealthServiceTests.swift
git commit -m "Extend ScoreComponent with explanation/tip and add opt-out to FinancialHealthService"
```

---

### Task 4: Update `CompassViewModel`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`

**Interfaces:**
- Consumes:
  - `FinancialHealthService.compute(transactions:expenseTransactions:budgetedCategories:ignoreSubscriptions:)`
  - `ITransactionRepository.saveSnapshot(_:)` and `.fetchSnapshots(limit:)`
  - `HealthScoreSnapshot(timestamp:score:savingsScore:stabilityScore:adherenceScore:subscriptionScore:)`
- Produces:
  - `CompassViewModel.scoreSnapshots: [HealthScoreSnapshot]`
  - `CompassViewModel.ignoreSubscriptions: Bool` (backed by UserDefaults, triggers recompute on set)

- [ ] **Step 1: Add `scoreSnapshots` and `ignoreSubscriptions` state**

In `InsightsViewModel.swift`, add to the `// MARK: - State` block after `var goalToEdit`:

```swift
    var scoreSnapshots: [HealthScoreSnapshot] = []
    var ignoreSubscriptions: Bool = UserDefaults.standard.bool(forKey: "healthScore.ignoreSubscriptions") {
        didSet {
            UserDefaults.standard.set(ignoreSubscriptions, forKey: "healthScore.ignoreSubscriptions")
            computeHealthScore()
        }
    }
```

- [ ] **Step 2: Update `computeHealthScore()`**

Replace the existing `computeHealthScore()` method:

```swift
    private func computeHealthScore() {
        let budgetedCategories = (try? repo.fetchCategories())?.filter { $0.monthlyBudget != nil } ?? []
        healthScore = healthService.compute(
            transactions: transactions,
            expenseTransactions: expenseTransactions,
            budgetedCategories: budgetedCategories,
            ignoreSubscriptions: ignoreSubscriptions
        )
        saveSnapshotIfNeeded()
        scoreSnapshots = (try? repo.fetchSnapshots(limit: 6)) ?? []
    }
```

- [ ] **Step 3: Add `saveSnapshotIfNeeded()`**

Add a new private method in `// MARK: - Computations`:

```swift
    private func saveSnapshotIfNeeded() {
        guard let score = healthScore else { return }
        let existing = (try? repo.fetchSnapshots(limit: 1)) ?? []
        let today = Calendar.current.startOfDay(for: Date.now)
        guard existing.first.map({ Calendar.current.startOfDay(for: $0.timestamp) }) != today else { return }

        let components = score.components
        let savingsScore = components.first(where: { $0.name == "Savings rate" })?.score ?? 0
        let stabilityScore = components.first(where: { $0.name == "Stability" })?.score ?? 0
        let adherenceScore = components.first(where: { $0.name == "Budget" })?.score ?? 0
        let subscriptionScore = components.first(where: { $0.name == "Subscriptions" })?.score ?? 0

        let snapshot = HealthScoreSnapshot(
            timestamp: Date.now,
            score: score.score,
            savingsScore: savingsScore,
            stabilityScore: stabilityScore,
            adherenceScore: adherenceScore,
            subscriptionScore: subscriptionScore
        )
        try? repo.saveSnapshot(snapshot)
    }
```

- [ ] **Step 4: Build to verify no compile errors**

```bash
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift
git commit -m "Add scoreSnapshots and ignoreSubscriptions to CompassViewModel"
```

---

### Task 5: Create `HealthScoreDetailView`

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift`

**Interfaces:**
- Consumes:
  - `HealthScore` from `CompassDataModels.swift`
  - `[HealthScoreSnapshot]` from Task 1
  - `Binding<Bool>` for `ignoreSubscriptions`
- Produces: `HealthScoreDetailView(healthScore:snapshots:ignoreSubscriptions:)` — presented as a sheet

- [ ] **Step 1: Create the file**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift`:

```swift
import SwiftUI
import Charts

struct HealthScoreDetailView: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    @Binding var ignoreSubscriptions: Bool

    private var sortedSnapshots: [HealthScoreSnapshot] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if sortedSnapshots.count >= 2 {
                        historySection
                    }
                    componentsSection
                    toggleSection
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Health Score")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - History Chart

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score History")
                .font(.headline)
                .foregroundStyle(.textPrimary)

            GlassCard {
                Chart(sortedSnapshots) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.accentIndigo)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Score", snapshot.score)
                    )
                    .foregroundStyle(Color.accentIndigo)
                    .symbolSize(36)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(Color.textDim)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisValueLabel()
                            .foregroundStyle(Color.textDim)
                    }
                }
                .frame(height: 140)
            }
        }
    }

    // MARK: - Component Breakdown

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakdown")
                .font(.headline)
                .foregroundStyle(.textPrimary)

            GlassCard {
                VStack(spacing: 16) {
                    ForEach(healthScore.components) { component in
                        componentRow(component)
                        if component.id != healthScore.components.last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func componentRow(_ component: ScoreComponent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(component.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(component.score) / \(component.max)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.textMid)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentIndigo.opacity(0.8))
                    .frame(width: max(0, CGFloat(component.score) / CGFloat(component.max)) * 200, height: 6)
            }
            .frame(height: 6)

            Text(component.explanation)
                .font(.caption)
                .foregroundStyle(.textDim)

            if let tip = component.tip {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.categoryAmber)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(Color.categoryAmber)
                }
                .padding(8)
                .background(Color.categoryAmber.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        GlassCard {
            Toggle(isOn: $ignoreSubscriptions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exclude subscriptions from score")
                        .font(.subheadline)
                        .foregroundStyle(.textPrimary)
                    Text("Redistributes those points across the other 3 categories")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
            .tint(Color.accentIndigo)
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift
git commit -m "Add HealthScoreDetailView with history chart, component breakdown, and opt-out toggle"
```

---

### Task 6: Update `HealthScoreCard` + `HealthScoreSection`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsView.swift`

**Interfaces:**
- Consumes:
  - `CompassViewModel.scoreSnapshots: [HealthScoreSnapshot]`
  - `CompassViewModel.ignoreSubscriptions: Bool`
  - `HealthScoreDetailView(healthScore:snapshots:ignoreSubscriptions:)` from Task 5

- [ ] **Step 1: Update `HealthScoreCard`**

Replace the entire file:

```swift
import SwiftUI
import Charts

struct HealthScoreCard: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    let onTap: () -> Void

    private var sortedSnapshots: [HealthScoreSnapshot] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    private var scoreColor: Color {
        switch healthScore.score {
        case 80...100: return .positive
        case 60...79:  return .accentIndigo
        case 40...59:  return .categoryAmber
        default:       return .negative
        }
    }

    private var sparklineColor: Color {
        guard sortedSnapshots.count >= 2,
              let first = sortedSnapshots.first,
              let last = sortedSnapshots.last else { return .accentIndigo }
        if last.score > first.score { return .positive }
        if last.score < first.score { return .negative }
        return .textDim
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                if sortedSnapshots.count >= 2 {
                    sparkline
                }
                HStack(alignment: .top, spacing: 20) {
                    arcGauge
                        .frame(width: 100, height: 100)

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(healthScore.score) / 100")
                                .font(.title2.bold())
                                .foregroundStyle(.textPrimary)
                            Text(healthScore.label)
                                .font(.caption)
                                .foregroundStyle(.textMid)
                        }

                        Divider()
                            .overlay(Color.white.opacity(0.1))

                        ForEach(healthScore.components) { component in
                            componentRow(component)
                        }
                    }
                }
            }
        }
        .onTapGesture { onTap() }
    }

    private var sparkline: some View {
        Chart(sortedSnapshots) { snapshot in
            LineMark(
                x: .value("Date", snapshot.timestamp),
                y: .value("Score", snapshot.score)
            )
            .foregroundStyle(sparklineColor)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .frame(height: 24)
    }

    private var arcGauge: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * Double(healthScore.score) / 100.0)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor.opacity(0.7), scoreColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.8), value: healthScore.score)

            VStack(spacing: 0) {
                Text("\(healthScore.score)")
                    .font(.title3.bold())
                    .foregroundStyle(scoreColor)
                Text("score")
                    .font(.caption2)
                    .foregroundStyle(.textDim)
            }
        }
    }

    private func componentRow(_ component: ScoreComponent) -> some View {
        HStack(spacing: 8) {
            Text(component.name)
                .font(.caption)
                .foregroundStyle(.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 3)
                    .fill(scoreColor.opacity(0.8))
                    .frame(width: 60 * CGFloat(component.score) / CGFloat(component.max), height: 5)
            }
            .frame(width: 60, height: 5)

            Text("\(component.score)")
                .font(.caption.bold())
                .foregroundStyle(.textMid)
                .frame(width: 20, alignment: .trailing)
        }
    }
}
```

- [ ] **Step 2: Update `HealthScoreSection`**

Replace the entire file:

```swift
import SwiftUI

struct HealthScoreSection: View {
    let healthScore: HealthScore?
    let snapshots: [HealthScoreSnapshot]
    @Binding var ignoreSubscriptions: Bool

    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsightsSectionHeader(title: "Health Score", subtitle: "How your finances are doing")
            if let score = healthScore {
                HealthScoreCard(healthScore: score, snapshots: snapshots) {
                    showingDetail = true
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let score = healthScore {
                HealthScoreDetailView(
                    healthScore: score,
                    snapshots: snapshots,
                    ignoreSubscriptions: $ignoreSubscriptions
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
```

- [ ] **Step 3: Update the call site in `InsightsView.swift`**

Find the line in `InsightsView.swift` that creates `HealthScoreSection` and update it to pass `snapshots` and `ignoreSubscriptions`. The existing call looks like:

```swift
HealthScoreSection(healthScore: viewModel.healthScore)
```

Replace it with:

```swift
HealthScoreSection(
    healthScore: viewModel.healthScore,
    snapshots: viewModel.scoreSnapshots,
    ignoreSubscriptions: Binding(
        get: { viewModel.ignoreSubscriptions },
        set: { viewModel.ignoreSubscriptions = $0 }
    )
)
```

- [ ] **Step 4: Build to verify no compile errors**

```bash
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj \
  -scheme PersonalFinanceTraker \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | grep -E "Test.*failed|Test Suite.*passed|error:"
```

Expected: all tests pass, no errors.

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift \
        PersonalFinanceTraker/PersonalFinanceTraker/Features/Insights/InsightsView.swift
git commit -m "Add sparkline to HealthScoreCard and wire HealthScoreDetailView sheet"
```
