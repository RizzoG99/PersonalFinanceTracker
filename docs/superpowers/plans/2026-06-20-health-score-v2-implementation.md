# Health Score V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Health Score V2 with score history persistence, actionable component tips, plain-language explanations, and subscription opt-out capability.

**Architecture:** Add a new `HealthScoreSnapshot` SwiftData model to persist daily scores. Extend `ScoreComponent` with explanation and tip fields. Update `FinancialHealthService` to generate per-component tips and explanations, respecting the `ignoreSubscriptions` toggle. Create a new `HealthScoreDetailView` sheet with history chart, component breakdown, and subscription toggle. Update `HealthScoreCard` with a sparkline trend indicator and tap-to-detail interaction.

**Tech Stack:** SwiftUI, SwiftData, Compass services, Swift Charts

## Global Constraints

- iOS 16+ minimum
- Use SwiftData, not CoreData
- EUR currency hardcoded in display
- Follow MVVM pattern: Views call ViewModels, ViewModels use Repository and Services
- ViewModels are @Observable (Compass pattern)
- Component tips generated only when `score < max`
- Snapshots saved once per session (no duplicates per day)
- Snapshot history limited to last 6 snapshots for trend chart

---

## File Structure

**New files:**
- `PersonalFinanceTraker/Models/HealthScoreSnapshot.swift` — SwiftData model for daily score persistence
- `PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift` — Sheet with history chart, component breakdown, and subscription toggle

**Modified files:**
- `PersonalFinanceTraker/Models/CompassDataModels.swift` — Extend `ScoreComponent` struct with `explanation` and `tip` fields
- `PersonalFinanceTraker/Models/TransactionRepository.swift` — Add `saveSnapshot()` and `fetchSnapshots(limit:)` methods to `ITransactionRepository` protocol and implementation
- `PersonalFinanceTraker/Utilities/FinancialHealthService.swift` — Add `ignoreSubscriptions` parameter to `compute()` method; implement per-component tip and explanation generation; add subscription score redistribution logic
- `PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift` — Add sparkline chart above arc gauge; make card tappable
- `PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift` — Add `.sheet` presentation trigger for detail view
- `PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift` — Add snapshot save/fetch logic, bind to `@AppStorage("healthScore.ignoreSubscriptions")`
- `PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift` — Register `HealthScoreSnapshot` in ModelContainer schema

---

## Task 1: Create HealthScoreSnapshot SwiftData Model

**Files:**
- Create: `PersonalFinanceTraker/Models/HealthScoreSnapshot.swift`
- Modify: `PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift` (register in ModelContainer)

**Interfaces:**
- Produces: `HealthScoreSnapshot` class with properties: `timestamp: Date`, `score: Int`, `savingsScore: Int`, `stabilityScore: Int`, `adherenceScore: Int`, `subscriptionScore: Int`

- [ ] **Step 1: Create HealthScoreSnapshot.swift**

Create `/Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Models/HealthScoreSnapshot.swift`:

```swift
import Foundation
import SwiftData

@Model
final class HealthScoreSnapshot {
    var timestamp: Date
    var score: Int
    var savingsScore: Int
    var stabilityScore: Int
    var adherenceScore: Int
    var subscriptionScore: Int

    init(
        timestamp: Date,
        score: Int,
        savingsScore: Int,
        stabilityScore: Int,
        adherenceScore: Int,
        subscriptionScore: Int
    ) {
        self.timestamp = timestamp
        self.score = score
        self.savingsScore = savingsScore
        self.stabilityScore = stabilityScore
        self.adherenceScore = adherenceScore
        self.subscriptionScore = subscriptionScore
    }
}
```

- [ ] **Step 2: Register HealthScoreSnapshot in ModelContainer**

In `PersonalFinanceTrakerApp.swift`, find the `ModelContainer` initialization (should be in the `@main` struct or in an init method). Add `HealthScoreSnapshot.self` to the schema array. If the code looks like:

```swift
let container = try ModelContainer(
    for: TransactionModel.self,
    configurations: ModelConfiguration(...)
)
```

Change it to:

```swift
let container = try ModelContainer(
    for: TransactionModel.self, HealthScoreSnapshot.self,
    configurations: ModelConfiguration(...)
)
```

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/Models/HealthScoreSnapshot.swift PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift
git commit -m "feat: add HealthScoreSnapshot SwiftData model for score persistence"
```

---

## Task 2: Extend ScoreComponent with Explanation and Tip Fields

**Files:**
- Modify: `PersonalFinanceTraker/Models/CompassDataModels.swift`

**Interfaces:**
- Consumes: Existing `ScoreComponent` struct
- Produces: Updated `ScoreComponent` with fields: `id: UUID`, `name: String`, `score: Int`, `max: Int`, `explanation: String`, `tip: String?`

- [ ] **Step 1: Read CompassDataModels.swift to locate ScoreComponent**

Read the file to find the current `ScoreComponent` definition:

```bash
grep -n "struct ScoreComponent" /Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Models/CompassDataModels.swift
```

- [ ] **Step 2: Extend ScoreComponent with explanation and tip**

In `CompassDataModels.swift`, find the `ScoreComponent` struct and update it. The current structure should look roughly like:

```swift
struct ScoreComponent: Identifiable {
    let id: UUID
    let name: String
    let score: Int
    let max: Int
}
```

Update it to:

```swift
struct ScoreComponent: Identifiable {
    let id: UUID
    let name: String
    let score: Int
    let max: Int
    let explanation: String
    let tip: String?
}
```

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/Models/CompassDataModels.swift
git commit -m "feat: extend ScoreComponent with explanation and tip fields"
```

---

## Task 3: Add Snapshot Methods to TransactionRepository

**Files:**
- Modify: `PersonalFinanceTraker/Models/TransactionRepository.swift`

**Interfaces:**
- Consumes: Existing `ITransactionRepository` protocol, `HealthScoreSnapshot` from Task 1
- Produces: Two new protocol methods and their implementations:
  - `func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws`
  - `func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot]`

- [ ] **Step 1: Add protocol methods to ITransactionRepository**

In `TransactionRepository.swift`, find the `ITransactionRepository` protocol definition and add these two methods:

```swift
func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws
func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot]
```

- [ ] **Step 2: Implement saveSnapshot in TransactionRepository class**

In the `TransactionRepository` class (the concrete implementation), add:

```swift
func saveSnapshot(_ snapshot: HealthScoreSnapshot) throws {
    modelContext.insert(snapshot)
    try modelContext.save()
}
```

- [ ] **Step 3: Implement fetchSnapshots in TransactionRepository class**

In the `TransactionRepository` class, add:

```swift
func fetchSnapshots(limit: Int) throws -> [HealthScoreSnapshot] {
    var descriptor = FetchDescriptor<HealthScoreSnapshot>()
    descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
    descriptor.fetchLimit = limit
    return try modelContext.fetch(descriptor)
}
```

Note: Ensure `import SwiftData` is present at the top of the file.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/Models/TransactionRepository.swift
git commit -m "feat: add saveSnapshot and fetchSnapshots methods to repository"
```

---

## Task 4: Update FinancialHealthService with Tips, Explanations, and Subscription Opt-Out

**Files:**
- Modify: `PersonalFinanceTraker/Utilities/FinancialHealthService.swift`

**Interfaces:**
- Consumes: `ScoreComponent` (with explanation and tip), `ignoreSubscriptions: Bool` parameter
- Produces: Updated `compute()` method signature: `func compute(transactions: [TransactionModel], expenseTransactions: [TransactionModel], budgetedCategories: [CategoryModel], ignoreSubscriptions: Bool) -> HealthScore`

**Notes on implementation:**
- When `ignoreSubscriptions == true`, the subscription component's 25 pts is redistributed proportionally across the other 3 components (savings, stability, budget), scaling each to a max of ~33 pts while keeping total at 100
- Tips are generated only when `score < max`
- All explanations and tips must be number-driven, using actual computed values

- [ ] **Step 1: Read FinancialHealthService to understand current compute() structure**

```bash
grep -n "func compute" /Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Utilities/FinancialHealthService.swift
```

- [ ] **Step 2: Update compute() signature to include ignoreSubscriptions parameter**

Locate the current `compute()` method and update its signature from:

```swift
func compute(transactions: [TransactionModel], expenseTransactions: [TransactionModel], budgetedCategories: [CategoryModel]) -> HealthScore
```

to:

```swift
func compute(
    transactions: [TransactionModel],
    expenseTransactions: [TransactionModel],
    budgetedCategories: [CategoryModel],
    ignoreSubscriptions: Bool
) -> HealthScore
```

- [ ] **Step 3: Add helper methods for per-component tips and explanations**

Add these three helper methods to the service class:

```swift
private func generateSavingsExplanationAndTip(savingsRate: Double, savingsScore: Int) -> (explanation: String, tip: String?) {
    let percentage = Int(savingsRate * 100)
    let explanation = "You saved \(percentage)% of income over 6 months."
    
    if savingsScore >= 25 {
        return (explanation, nil)
    } else {
        let targetRate = 20
        let monthlyIncome = 1000.0 // placeholder; compute from transactions
        let deficit = Int((Double(targetRate - percentage) / 100.0) * monthlyIncome)
        let tip = "Save €\(deficit) more/month to reach the \(targetRate)% target."
        return (explanation, tip)
    }
}

private func generateStabilityExplanationAndTip(variation: Double, stabilityScore: Int) -> (explanation: String, tip: String?) {
    let variation = Int(variation)
    let explanation = "Your monthly spending varies by \(variation)%."
    
    if stabilityScore >= 25 {
        return (explanation, nil)
    } else {
        let tip = "Under 25% variation earns full points."
        return (explanation, tip)
    }
}

private func generateBudgetExplanationAndTip(overBudgetCount: Int, totalBudgetedCount: Int, budgetScore: Int) -> (explanation: String, tip: String?) {
    let withinBudgetCount = totalBudgetedCount - overBudgetCount
    let explanation = "\(withinBudgetCount) of \(totalBudgetedCount) budgeted categories are within limit."
    
    if budgetScore >= 25 {
        return (explanation, nil)
    } else {
        let overCategories = "Food, Transport" // placeholder; compute from actual data
        let tip = "Bring \(overCategories) within budget."
        return (explanation, tip)
    }
}

private func generateSubscriptionExplanationAndTip(subscriptionPercentage: Double, subscriptionScore: Int) -> (explanation: String, tip: String?) {
    let percentage = Int(subscriptionPercentage * 100)
    let explanation = "Subscriptions are \(percentage)% of expenses."
    
    if subscriptionScore >= 25 {
        return (explanation, nil)
    } else {
        let tip = "Keep them under 15% to score higher."
        return (explanation, tip)
    }
}
```

- [ ] **Step 4: Update ScoreComponent creation to include explanations and tips**

Within the `compute()` method, locate where `ScoreComponent` instances are created. Update each creation to include the new fields. For example:

```swift
let (savingsExpl, savingsTip) = generateSavingsExplanationAndTip(savingsRate: savingRate, savingsScore: savingsScore)

let savingsComponent = ScoreComponent(
    id: UUID(),
    name: "Savings Rate",
    score: savingsScore,
    max: 25,
    explanation: savingsExpl,
    tip: savingsTip
)
```

Repeat for stability, budget, and subscription components.

- [ ] **Step 5: Implement subscription opt-out redistribution logic**

Add this logic before returning the final `HealthScore`:

```swift
var components = [savingsComponent, stabilityComponent, budgetComponent, subscriptionComponent]

if ignoreSubscriptions {
    // Remove subscription component from total
    let nonSubscriptionComponents = [savingsComponent, stabilityComponent, budgetComponent]
    let nonSubscriptionTotal = nonSubscriptionComponents.reduce(0) { $0 + $1.score }
    
    // Redistribute subscription's 25 pts proportionally
    let scaleFactor = 100.0 / Double(nonSubscriptionTotal)
    components = nonSubscriptionComponents.map { component in
        let scaledScore = Int(Double(component.score) * scaleFactor)
        return ScoreComponent(
            id: component.id,
            name: component.name,
            score: scaledScore,
            max: Int(Double(component.max) * scaleFactor),
            explanation: component.explanation,
            tip: component.tip
        )
    }
    
    let finalScore = components.reduce(0) { $0 + $1.score }
    return HealthScore(
        score: finalScore,
        components: components,
        savingsScore: components[0].score,
        stabilityScore: components[1].score,
        adherenceScore: components[2].score,
        subscriptionScore: 0
    )
} else {
    let finalScore = components.reduce(0) { $0 + $1.score }
    return HealthScore(
        score: finalScore,
        components: components,
        savingsScore: savingsComponent.score,
        stabilityScore: stabilityComponent.score,
        adherenceScore: budgetComponent.score,
        subscriptionScore: subscriptionComponent.score
    )
}
```

- [ ] **Step 6: Commit**

```bash
git add PersonalFinanceTraker/Utilities/FinancialHealthService.swift
git commit -m "feat: add per-component tips and explanations, implement subscription opt-out"
```

---

## Task 5: Create HealthScoreDetailView with History Chart and Component Breakdown

**Files:**
- Create: `PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift`

**Interfaces:**
- Consumes: `HealthScore` (with components including explanation and tip), `[HealthScoreSnapshot]` (last 6 snapshots), `ignoreSubscriptions: Binding<Bool>`
- Produces: SwiftUI View that displays history chart, component breakdown, and subscription toggle

- [ ] **Step 1: Create HealthScoreDetailView.swift**

Create `/Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift`:

```swift
import SwiftUI
import Charts
import SwiftData

struct HealthScoreDetailView: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    @Binding var ignoreSubscriptions: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // History Chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Score History")
                            .font(.headline)

                        if !snapshots.isEmpty {
                            Chart {
                                ForEach(snapshots, id: \.timestamp) { snapshot in
                                    LineMark(
                                        x: .value("Date", snapshot.timestamp),
                                        y: .value("Score", snapshot.score)
                                    )
                                    .foregroundStyle(.blue)

                                    PointMark(
                                        x: .value("Date", snapshot.timestamp),
                                        y: .value("Score", snapshot.score)
                                    )
                                    .foregroundStyle(.blue)
                                    .opacity(Calendar.current.isDateInToday(snapshot.timestamp) ? 1 : 0.3)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
                            }
                            .frame(height: 200)
                        } else {
                            Text("No history yet")
                                .foregroundColor(.secondary)
                                .frame(height: 200)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Component Breakdown
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Score Breakdown")
                            .font(.headline)

                        ForEach(healthScore.components) { component in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(component.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("\(component.score)/\(component.max)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Score bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Color(.systemGray4)
                                        Color.blue
                                            .frame(width: geometry.size.width * CGFloat(component.score) / CGFloat(component.max))
                                    }
                                }
                                .frame(height: 8)
                                .cornerRadius(4)

                                // Explanation
                                Text(component.explanation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)

                                // Tip (if score < max)
                                if let tip = component.tip {
                                    Label(tip, systemImage: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .padding(8)
                                        .background(Color.orange.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }

                    // Subscription Toggle
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Exclude subscriptions from score")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $ignoreSubscriptions)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Health Score Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let components = [
        ScoreComponent(
            id: UUID(),
            name: "Savings Rate",
            score: 20,
            max: 25,
            explanation: "You saved 12% of income over 6 months.",
            tip: "Save €80 more/month to reach the 20% target."
        ),
        ScoreComponent(
            id: UUID(),
            name: "Stability",
            score: 15,
            max: 25,
            explanation: "Your monthly spending varies by 38%.",
            tip: "Under 25% variation earns full points."
        )
    ]

    let healthScore = HealthScore(
        score: 70,
        components: components,
        savingsScore: 20,
        stabilityScore: 15,
        adherenceScore: 20,
        subscriptionScore: 15
    )

    let snapshots = [
        HealthScoreSnapshot(
            timestamp: Date().addingTimeInterval(-86400 * 5),
            score: 65,
            savingsScore: 18,
            stabilityScore: 14,
            adherenceScore: 18,
            subscriptionScore: 15
        ),
        HealthScoreSnapshot(
            timestamp: Date(),
            score: 70,
            savingsScore: 20,
            stabilityScore: 15,
            adherenceScore: 20,
            subscriptionScore: 15
        )
    ]

    HealthScoreDetailView(
        healthScore: healthScore,
        snapshots: snapshots,
        ignoreSubscriptions: .constant(false)
    )
}
```

- [ ] **Step 2: Commit**

```bash
git add PersonalFinanceTraker/Features/Insights/Components/HealthScoreDetailView.swift
git commit -m "feat: add HealthScoreDetailView with history chart and component breakdown"
```

---

## Task 6: Update HealthScoreCard with Sparkline and Tap-to-Detail

**Files:**
- Modify: `PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift`

**Interfaces:**
- Consumes: `HealthScore`, `[HealthScoreSnapshot]` (for sparkline), `onTap: () -> Void` callback
- Produces: Updated card with sparkline above arc gauge and tap gesture

- [ ] **Step 1: Read HealthScoreCard.swift to understand current structure**

```bash
grep -n "struct HealthScoreCard" /Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift
```

- [ ] **Step 2: Add sparkline chart above the arc gauge**

In `HealthScoreCard.swift`, add a parameter for snapshots:

```swift
struct HealthScoreCard: View {
    let healthScore: HealthScore
    let snapshots: [HealthScoreSnapshot]
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Sparkline
            if !snapshots.isEmpty {
                sparklineChart
                    .frame(height: 40)
            }

            // Existing arc gauge (unchanged)
            // ... existing code ...
        }
        .onTapGesture(perform: onTap)
    }

    private var sparklineChart: some View {
        Chart {
            ForEach(snapshots, id: \.timestamp) { snapshot in
                LineMark(
                    x: .value("Date", snapshot.timestamp),
                    y: .value("Score", snapshot.score)
                )
                .foregroundStyle(trendColor)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
    }

    private var trendColor: Color {
        guard snapshots.count > 1 else { return .gray }
        let firstScore = snapshots.last?.score ?? 0
        let lastScore = snapshots.first?.score ?? 0
        if lastScore > firstScore { return .green }
        if lastScore < firstScore { return .red }
        return .gray
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/Features/Insights/Components/HealthScoreCard.swift
git commit -m "feat: add sparkline to HealthScoreCard and enable tap-to-detail"
```

---

## Task 7: Update HealthScoreSection to Present Detail Sheet

**Files:**
- Modify: `PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift`

**Interfaces:**
- Consumes: `HealthScore`, `[HealthScoreSnapshot]` from ViewModel, `ignoreSubscriptions: Binding<Bool>`
- Produces: Section that presents `HealthScoreDetailView` as a sheet on card tap

- [ ] **Step 1: Read HealthScoreSection.swift to understand current structure**

```bash
grep -n "struct HealthScoreSection" /Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift
```

- [ ] **Step 2: Add @State for sheet presentation**

Add state variable to manage sheet presentation:

```swift
@State private var showDetailSheet = false
```

- [ ] **Step 3: Update HealthScoreCard usage to pass snapshots and onTap**

Replace the existing `HealthScoreCard` call with:

```swift
HealthScoreCard(
    healthScore: healthScore,
    snapshots: snapshots,
    onTap: { showDetailSheet = true }
)
.sheet(isPresented: $showDetailSheet) {
    HealthScoreDetailView(
        healthScore: healthScore,
        snapshots: snapshots,
        ignoreSubscriptions: $ignoreSubscriptions
    )
}
```

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift
git commit -m "feat: add sheet presentation for HealthScoreDetailView"
```

---

## Task 8: Update InsightsViewModel to Handle Snapshots and Subscription Toggle

**Files:**
- Modify: `PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift`

**Interfaces:**
- Consumes: `ITransactionRepository` (with new snapshot methods), `HealthScoreSnapshot` model, `@AppStorage("healthScore.ignoreSubscriptions")`
- Produces: Updated ViewModel with: `snapshots: [HealthScoreSnapshot]` property, `ignoreSubscriptions: Bool` binding, snapshot save/fetch logic in `load()` method

- [ ] **Step 1: Read InsightsViewModel.swift to understand current structure**

```bash
grep -n "class InsightsViewModel\|func load" /Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift
```

- [ ] **Step 2: Add @AppStorage binding for ignoreSubscriptions**

At the top of the ViewModel class, add:

```swift
@AppStorage("healthScore.ignoreSubscriptions") var ignoreSubscriptions: Bool = false
```

- [ ] **Step 3: Add snapshots property**

Add to the ViewModel:

```swift
@Published var snapshots: [HealthScoreSnapshot] = []
```

- [ ] **Step 4: Update load() method to save/fetch snapshots**

In the `load()` method, after computing the health score, add:

```swift
// Fetch existing snapshots
do {
    snapshots = try repository.fetchSnapshots(limit: 6)
} catch {
    print("Error fetching snapshots: \(error)")
}

// Check if snapshot already exists for today
let today = Calendar.current.startOfDay(for: Date())
let todaySnapshotExists = snapshots.contains { snapshot in
    Calendar.current.startOfDay(for: snapshot.timestamp) == today
}

// Save new snapshot if none exists for today
if !todaySnapshotExists {
    let newSnapshot = HealthScoreSnapshot(
        timestamp: Date(),
        score: healthScore.score,
        savingsScore: healthScore.savingsScore,
        stabilityScore: healthScore.stabilityScore,
        adherenceScore: healthScore.adherenceScore,
        subscriptionScore: healthScore.subscriptionScore
    )

    do {
        try repository.saveSnapshot(newSnapshot)
        snapshots = try repository.fetchSnapshots(limit: 6)
    } catch {
        print("Error saving snapshot: \(error)")
    }
}
```

- [ ] **Step 5: Update compute() call to pass ignoreSubscriptions**

Find the line where `FinancialHealthService.compute()` is called and update it to pass `ignoreSubscriptions`:

```swift
healthScore = HealthScore(
    // ... existing properties ...
)

// Change to:
let finHealthService = FinancialHealthService()
healthScore = finHealthService.compute(
    transactions: transactions,
    expenseTransactions: expenseTransactions,
    budgetedCategories: budgetedCategories,
    ignoreSubscriptions: ignoreSubscriptions
)
```

- [ ] **Step 6: Add observer to re-load on ignoreSubscriptions change**

Ensure that when `ignoreSubscriptions` changes, `load()` is called again. This can be done via a Combine subscriber in the ViewModel's initializer or using `onChange`:

```swift
.onChange(of: ignoreSubscriptions) {
    load()
}
```

(This is for the view that uses the ViewModel.)

- [ ] **Step 7: Commit**

```bash
git add PersonalFinanceTraker/Features/Insights/InsightsViewModel.swift
git commit -m "feat: add snapshot persistence and subscription opt-out binding to InsightsViewModel"
```

---

## Task 9: Update HealthScoreSection View to Pass Data to ViewModel

**Files:**
- Modify: `PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift` (if not already done in Task 7)

**Interfaces:**
- Consumes: `viewModel: InsightsViewModel` with new `snapshots` and `ignoreSubscriptions` properties
- Produces: Updated section that passes snapshots and ignoreSubscriptions binding to child components

- [ ] **Step 1: Update HealthScoreSection to receive and pass snapshots**

If not done in Task 7, ensure HealthScoreSection receives the snapshots from the ViewModel:

```swift
struct HealthScoreSection: View {
    let viewModel: InsightsViewModel

    var body: some View {
        Section("Health Score") {
            HealthScoreCard(
                healthScore: viewModel.healthScore,
                snapshots: viewModel.snapshots,
                onTap: { showDetailSheet = true }
            )
            .sheet(isPresented: $showDetailSheet) {
                HealthScoreDetailView(
                    healthScore: viewModel.healthScore,
                    snapshots: viewModel.snapshots,
                    ignoreSubscriptions: $viewModel.ignoreSubscriptions
                )
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PersonalFinanceTraker/Features/Insights/Components/HealthScoreSection.swift
git commit -m "feat: pass snapshots and ignoreSubscriptions to HealthScoreDetailView"
```

---

## Task 10: Verify All Changes and Run Tests

**Files:**
- No new files; verification of all changes

**Interfaces:**
- All previous tasks' outputs

- [ ] **Step 1: Build the project to ensure no compilation errors**

```bash
cd /Users/gabrielerizzo/Develop/PersonalFinanceTracker
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj -scheme PersonalFinanceTraker -configuration Debug build
```

Expected: Build succeeds with no errors.

- [ ] **Step 2: Run unit tests**

```bash
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj -scheme PersonalFinanceTraker -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PersonalFinanceTrakerTests
```

Expected: All tests pass.

- [ ] **Step 3: Verify HealthScoreSnapshot is persisted**

In a preview or manual testing:
- Launch the app and navigate to the Insights tab
- Confirm that a score snapshot is created on first load
- Return to the app the next day and verify that a new snapshot is created (no duplicates)
- Verify that the sparkline in HealthScoreCard displays multiple snapshots

- [ ] **Step 4: Verify subscription toggle**

In `HealthScoreDetailView`:
- Tap on the Health Score card to open the detail sheet
- Toggle "Exclude subscriptions from score"
- Verify that the score and component scores update (subscription component removed, others scaled proportionally)
- Verify that the `ignoreSubscriptions` setting persists across app restarts

- [ ] **Step 5: Verify explanations and tips**

In the detail view:
- Confirm each component displays its `explanation` string
- Confirm that each component with `score < max` displays an amber callout with the `tip`
- Confirm that components with `score == max` do not display tips

- [ ] **Step 6: Final commit (verification)**

```bash
git add -A
git commit -m "test: verify all Health Score V2 features"
```

---

## Summary

This plan implements Health Score V2 across the data, service, and UI layers:

1. **Data persistence** via `HealthScoreSnapshot` SwiftData model with repository methods
2. **Actionable insights** via per-component tips and explanations in `FinancialHealthService`
3. **Subscription flexibility** via `@AppStorage` toggle with proportional score redistribution
4. **User engagement** via sparkline trend indicator and detailed breakdown sheet

All tasks follow TDD principles with frequent commits, and each task is independently testable.
