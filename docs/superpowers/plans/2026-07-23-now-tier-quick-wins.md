# Now-Tier Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the six roadmap "Now" items: README refresh, CreditScoreCard deletion, Dashboard anomaly callout, persisted import mappings, daily logging reminder, and an App Intent for background transaction quick-add.

**Architecture:** Six independent changes on one branch, cheapest first. New logic lands as small pure functions/services (`ReminderScheduler`, `ImportProfileStore`, `QuickAddService`, `DashboardViewModel.computeAnomalyCallout`) tested with Swift Testing; UI wiring reuses existing patterns (`@Observable` view models, `AppSettings`-style UserDefaults, snapshot value types, `TransactionActor` repository).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppIntents, UserNotifications, CryptoKit, Swift Testing.

## Global Constraints

- **NEVER run `xcodebuild` in Bash.** Build/test ONLY via Xcode MCP tools. Two steps every time: (1) `ToolSearch` with query `select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests`, (2) call the tool with `tabIdentifier: "windowtab1"`.
- Directory is `PersonalFinanceTraker` (missing 'c') — everywhere, including test imports: `@testable import PersonalFinanceTraker`.
- Expenses are **negative** `Decimal`; income positive. Currency is EUR hardcoded.
- Tests use Swift Testing (`@Test`, `#expect`), NOT XCTest.
- Commit messages: conventional style, **no Co-Authored-By line**.
- The Xcode project uses filesystem-synchronized groups — new `.swift` files under `PersonalFinanceTraker/PersonalFinanceTraker/` or `PersonalFinanceTrakerTests/` join their targets automatically; no pbxproj edits.
- After all tasks: run `graphify update .` (AST-only, no API cost).

---

### Task 1: README refresh

**Files:**
- Modify: `README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update the Features and Work in Progress sections**

In `README.md`, replace the Features list and the Work in Progress section:

```markdown
## Features

- **Dashboard** — total balance, income/expense summary for the current pay cycle, and recent transactions
- **Activity** — full transaction list with grouped history, live search with type/date/amount filters, and swipe-to-delete with undo
- **Insights** — health score, spending forecast, goal pockets, habit insights, category trends and charts
- **Categories** — customizable categories with icons and colors
- **Add / Edit transactions** — quick entry sheet with category, amount, date, and notes
- **Import / Export** — CSV and Excel import with column & category mapping; CSV/Excel export
- **Security** — Face ID / Touch ID and PIN lock; PIN-confirmed delete-all-data
- **Profile** — pay cycle configuration and personal info
```

and

```markdown
## Work in Progress

- iCloud sync
- Budgeting / spending limits
- Recurring transactions
- Home-screen widgets
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README feature list; search and biometrics are shipped"
```

---

### Task 2: Delete CreditScoreCard

**Files:**
- Delete: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Credit/Components/CreditScoreCard.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Credit/CreditView.swift:23-27`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Credit/CreditViewModel.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — pure deletion. Note: the Credit tab itself is currently commented out in `MainTabView.swift:46-48`; leave that comment block untouched.

- [ ] **Step 1: Remove the card from CreditView**

In `CreditView.swift`, delete lines 23–27:

```swift
                    CreditScoreCard(
                        creditScore: viewModel.creditScore,
                        creditStatus: viewModel.creditStatusLabel,
                        onEditScore: { viewModel.updateCreditScore($0) }
                    )
```

- [ ] **Step 2: Remove score state from CreditViewModel**

In `CreditViewModel.swift` delete:
- property `var creditScore: Int` (line 11)
- constant `private let scoreKey = "credit_score_value"` (line 15)
- the two `init` lines that read the stored score (lines 19–20: `let stored = ...` and `creditScore = ...`)
- method `updateCreditScore(_:)` (lines 58–61)
- computed property `creditStatusLabel` (lines 80–88)

- [ ] **Step 3: Delete the component file**

```bash
git rm PersonalFinanceTraker/PersonalFinanceTraker/Features/Credit/Components/CreditScoreCard.swift
```

- [ ] **Step 4: Build**

`ToolSearch` query `select:mcp__xcode__BuildProject`, then `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds (no remaining references to `CreditScoreCard`, `creditScore`, `creditStatusLabel`, or `updateCreditScore` — if the build fails on one, remove that reference too).

- [ ] **Step 5: Commit**

```bash
git add -A PersonalFinanceTraker/PersonalFinanceTraker/Features/Credit
git commit -m "refactor: delete CreditScoreCard placeholder and manual score state"
```

---

### Task 3: Dashboard anomaly callout

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard/DashboardViewModel.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard/Components/AnomalyCalloutView.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard/DashboardView.swift:19`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/DashboardViewModelTests.swift` (existing file — append tests)

**Interfaces:**
- Consumes: `ChartDataService.generateChartData(from:for:referenceDate:payCycleStartDay:) -> [ChartDataPoint]`, `TimelineAnomalyService.annotateWithSpikes(_:) -> [TimelineDataPoint]` (fields: `date`, `period`, `expenses`, `isSpike`), `PayCycleService.currentFinancialMonth(startDay:) -> (Date, Date)`, `TransactionSnapshot.test(...)` factory.
- Produces: `struct AnomalyCallout: Equatable { let message: String; let dismissKey: String }`, `DashboardViewModel.anomalyCallout: AnomalyCallout?`, `DashboardViewModel.dismissAnomaly()`, `nonisolated static func computeAnomalyCallout(_ transactions: [TransactionSnapshot], payCycleStartDay: Int, dismissedKey: String?) -> AnomalyCallout?`.

- [ ] **Step 1: Write the failing tests**

Append to `DashboardViewModelTests.swift` (inside the existing suite, matching its imports):

```swift
@Test func anomalyCalloutDetectsSpike() {
    // One large expense today, otherwise-quiet pay cycle → spike week flagged
    let transactions = [
        TransactionSnapshot.test(timestamp: .now, amount: -1000, category: "Shopping")
    ]
    let callout = DashboardViewModel.computeAnomalyCallout(
        transactions, payCycleStartDay: 1, dismissedKey: nil
    )
    #expect(callout != nil)
    #expect(callout?.message.contains("€") == true)
}

@Test func anomalyCalloutRespectsDismissal() {
    let transactions = [
        TransactionSnapshot.test(timestamp: .now, amount: -1000, category: "Shopping")
    ]
    let first = DashboardViewModel.computeAnomalyCallout(
        transactions, payCycleStartDay: 1, dismissedKey: nil
    )
    let second = DashboardViewModel.computeAnomalyCallout(
        transactions, payCycleStartDay: 1, dismissedKey: first?.dismissKey
    )
    #expect(second == nil)
}

@Test func anomalyCalloutNilWithoutSpike() {
    let callout = DashboardViewModel.computeAnomalyCallout(
        [], payCycleStartDay: 1, dismissedKey: nil
    )
    #expect(callout == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

`ToolSearch` query `select:mcp__xcode__RunSomeTests,mcp__xcode__BuildProject`, then `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `DashboardViewModelTests`.
Expected: compile FAILURE — `computeAnomalyCallout` and `AnomalyCallout` not defined.

- [ ] **Step 3: Implement in DashboardViewModel**

Add above the class in `DashboardViewModel.swift`:

```swift
struct AnomalyCallout: Equatable {
    let message: String
    let dismissKey: String
}
```

Add inside `DashboardViewModel`:

```swift
var anomalyCallout: AnomalyCallout? = nil
private static let dismissedAnomalyDefaultsKey = "dismissedAnomalyCalloutKey"

nonisolated static func computeAnomalyCallout(
    _ transactions: [TransactionSnapshot],
    payCycleStartDay: Int,
    dismissedKey: String?
) -> AnomalyCallout? {
    let points = ChartDataService().generateChartData(
        from: transactions, for: .month, payCycleStartDay: payCycleStartDay
    )
    let annotated = TimelineAnomalyService().annotateWithSpikes(points)
    guard let spike = annotated.last(where: { $0.isSpike }) else { return nil }
    let (cycleStart, _) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay)
    let key = "\(cycleStart.timeIntervalSince1970)_\(spike.period)"
    guard key != dismissedKey else { return nil }
    let amount = Double(truncating: spike.expenses as NSDecimalNumber)
    let message = "Unusually high spending in \(spike.period): \(amount.formatted(.currency(code: "EUR")))"
    return AnomalyCallout(message: message, dismissKey: key)
}

func dismissAnomaly() {
    if let key = anomalyCallout?.dismissKey {
        UserDefaults.standard.set(key, forKey: Self.dismissedAnomalyDefaultsKey)
    }
    anomalyCallout = nil
}
```

At the end of `calculateMetrics()` (after `recentTransactions = recent`), add — note `payCycleStartDay` here is the LOCAL constant already captured at the top of `calculateMetrics()` (`let payCycleStartDay = payCycleStartDay()` shadows the closure property; calling it as a function here would not compile):

```swift
anomalyCallout = Self.computeAnomalyCallout(
    transactions,
    payCycleStartDay: payCycleStartDay,
    dismissedKey: UserDefaults.standard.string(forKey: Self.dismissedAnomalyDefaultsKey)
)
```

- [ ] **Step 4: Run tests to verify they pass**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `DashboardViewModelTests`.
Expected: PASS (all, including pre-existing tests).

- [ ] **Step 5: Create the callout view**

Create `Features/Dashboard/Components/AnomalyCalloutView.swift`:

```swift
//
//  AnomalyCalloutView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct AnomalyCalloutView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.textMid)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.textDim)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.12))
        )
    }
}

#Preview {
    AnomalyCalloutView(
        message: "Unusually high spending in Week 3: €412.50",
        onDismiss: {}
    )
    .padding()
    .appBackground()
    .preferredColorScheme(.dark)
}
```

(If `.textMid`/`.textDim` don't resolve in this target scope, they're the existing design-token shape styles used in `ProfileView.swift` — keep them.)

- [ ] **Step 6: Insert into DashboardView**

In `DashboardView.swift`, after `BalanceCardView()` (line 19), add:

```swift
                    if let callout = viewModel.anomalyCallout {
                        AnomalyCalloutView(message: callout.message) {
                            viewModel.dismissAnomaly()
                        }
                    }
```

- [ ] **Step 7: Build**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Dashboard PersonalFinanceTraker/PersonalFinanceTrakerTests/DashboardViewModelTests.swift
git commit -m "feat: surface spending anomaly callout on Dashboard"
```

---

### Task 4: Import mapping memory

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ImportProfileStore.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVColumnMapper.swift:8-24` (Codable conformance)
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/ImportFlowView.swift:74-78`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/ImportProfileStoreTests.swift` (new)

**Interfaces:**
- Consumes: `ColumnMapping` (struct in CSVColumnMapper.swift), `CSVFile.headers: [String]`, `CSVFile.delimiter: Character`, `CategorySnapshot.id: UUID`, `String.removingLeadingEmoji`.
- Produces: `struct ImportProfile: Codable, Equatable { var mapping: ColumnMapping; var categorySelections: [String: String] }`; `final class ImportProfileStore` with `init(defaults: UserDefaults = .standard)`, `static func signature(headers: [String], delimiter: Character) -> String`, `func profile(for signature: String) -> ImportProfile?`, `func save(_ profile: ImportProfile, for signature: String)`; `TransactionListViewModel.applySavedCategorySelections()`.

- [ ] **Step 1: Make ColumnMapping Codable**

In `CSVColumnMapper.swift`:
- change `enum SignConvention: String, CaseIterable {` to `enum SignConvention: String, CaseIterable, Codable {`
- change `struct ColumnMapping {` to `struct ColumnMapping: Codable, Equatable {`

- [ ] **Step 2: Write the failing tests**

Create `PersonalFinanceTrakerTests/Utilities/ImportProfileStoreTests.swift`:

```swift
//
//  ImportProfileStoreTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct ImportProfileStoreTests {

    private func freshStore() -> ImportProfileStore {
        ImportProfileStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test func signatureIsStableForSameHeaders() {
        let a = ImportProfileStore.signature(headers: ["Date", "Amount", "Note"], delimiter: ";")
        let b = ImportProfileStore.signature(headers: ["Date", "Amount", "Note"], delimiter: ";")
        #expect(a == b)
    }

    @Test func signatureDiffersForDifferentHeadersOrDelimiter() {
        let base = ImportProfileStore.signature(headers: ["Date", "Amount"], delimiter: ";")
        #expect(base != ImportProfileStore.signature(headers: ["Date", "Importo"], delimiter: ";"))
        #expect(base != ImportProfileStore.signature(headers: ["Date", "Amount"], delimiter: ","))
    }

    @Test func saveAndLoadRoundTrip() {
        let store = freshStore()
        var mapping = ColumnMapping()
        mapping.dateColumn = "Date"
        mapping.amountColumn = "Amount"
        mapping.dateFormat = "dd/MM/yyyy"
        mapping.signConvention = .allExpenses
        let profile = ImportProfile(
            mapping: mapping,
            categorySelections: ["🍕 Food": UUID().uuidString]
        )
        let sig = ImportProfileStore.signature(headers: ["Date", "Amount"], delimiter: ";")

        store.save(profile, for: sig)

        #expect(store.profile(for: sig) == profile)
        #expect(store.profile(for: "other") == nil)
    }

    @Test func savingAgainOverwrites() {
        let store = freshStore()
        let sig = ImportProfileStore.signature(headers: ["Date"], delimiter: ",")
        var mapping = ColumnMapping()
        mapping.dateColumn = "Date"
        store.save(ImportProfile(mapping: mapping, categorySelections: [:]), for: sig)
        mapping.dateFormat = "yyyy-MM-dd"
        let updated = ImportProfile(mapping: mapping, categorySelections: ["A": "B"])
        store.save(updated, for: sig)
        #expect(store.profile(for: sig) == updated)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `ImportProfileStoreTests`.
Expected: compile FAILURE — `ImportProfileStore` / `ImportProfile` not defined.

- [ ] **Step 4: Implement the store**

Create `Utilities/ImportProfileStore.swift`:

```swift
//
//  ImportProfileStore.swift
//  PersonalFinanceTraker
//
//  Remembers column + category mappings per bank-file layout so re-importing
//  a monthly statement is prefilled. Stored in UserDefaults (not SwiftData)
//  on purpose: profiles survive Delete All Data and stay decoupled from the
//  model container.
//

import Foundation
import CryptoKit

struct ImportProfile: Codable, Equatable {
    var mapping: ColumnMapping
    var categorySelections: [String: String]  // CSV category name → CategoryModel UUID string
}

final class ImportProfileStore {
    // ponytail: UserDefaults JSON blob; move to SwiftData if profiles ever need syncing
    private let key = "importProfiles.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Layout fingerprint: header row + delimiter. Unit separator between
    /// headers so ["a,b"] and ["a","b"] can't collide.
    static func signature(headers: [String], delimiter: Character) -> String {
        let payload = headers.joined(separator: "\u{1F}") + "\u{1E}" + String(delimiter)
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func profile(for signature: String) -> ImportProfile? {
        all()[signature]
    }

    func save(_ profile: ImportProfile, for signature: String) {
        var profiles = all()
        profiles[signature] = profile
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: key)
        }
    }

    private func all() -> [String: ImportProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([String: ImportProfile].self, from: data)
        else { return [:] }
        return profiles
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `ImportProfileStoreTests`.
Expected: PASS (4 tests).

- [ ] **Step 6: Wire prefill into TransactionListViewModel**

In `TransactionListViewModel.swift`, add to the `// MARK: - CSV Import` property block:

```swift
    @ObservationIgnored var importProfileStore = ImportProfileStore()
    @ObservationIgnored private(set) var currentImportSignature: String? = nil
    @ObservationIgnored private var savedCategorySelections: [String: String]? = nil
```

In `loadCSVFile(from:)`, replace the two lines

```swift
                columnMapping = mapping
                columnMapping.defaultCurrency = currencyService.baseCurrency
```

with

```swift
                columnMapping = mapping
                applyImportProfileIfAvailable(for: file)
                columnMapping.defaultCurrency = currencyService.baseCurrency
```

In `applySheet(_:of:)`, replace

```swift
        columnMapping = CSVColumnMapper.autoDetect(from: file)
        columnMapping.defaultCurrency = currencyService.baseCurrency
```

with

```swift
        columnMapping = CSVColumnMapper.autoDetect(from: file)
        applyImportProfileIfAvailable(for: file)
        columnMapping.defaultCurrency = currencyService.baseCurrency
```

Add these methods below `applySheet`:

```swift
    /// Prefill the wizard from a previously saved profile for this file layout.
    private func applyImportProfileIfAvailable(for file: CSVFile) {
        let signature = ImportProfileStore.signature(
            headers: file.headers, delimiter: file.delimiter
        )
        currentImportSignature = signature
        guard let profile = importProfileStore.profile(for: signature) else { return }
        columnMapping = profile.mapping
        savedCategorySelections = profile.categorySelections
    }

    /// Called after csvCategories are computed; prefills selections that still
    /// point at an existing category. Unknown/deleted categories fall back to
    /// the normal auto-mapping flow.
    func applySavedCategorySelections() {
        guard let saved = savedCategorySelections else { return }
        let validIds = Set(availableCategories.map { $0.id.uuidString })
        for category in csvCategories {
            if let selection = saved[category], validIds.contains(selection) {
                categoryResolutionSelections[category] = selection
            }
        }
    }
```

In `resetImportSelectionState()` and `cancelImport()`, add:

```swift
        savedCategorySelections = nil
        currentImportSignature = nil
```

In `confirmImport(_:)`, immediately after Step 3's `for` loop (the one filling `newCategoryPersistentIds`), add:

```swift
            // Persist the profile so the next import of this layout is prefilled.
            // "__new__" selections are stored as the just-created category's UUID.
            if let signature = currentImportSignature {
                var resolvedSelections = categoryResolutionSelections
                for (csvCatName, selection) in resolvedSelections where selection == "__new__" {
                    let createdName = csvCatName.removingLeadingEmoji
                        .trimmingCharacters(in: .whitespaces)
                    if let created = updatedCategories.first(where: { $0.name == createdName }) {
                        resolvedSelections[csvCatName] = created.id.uuidString
                    }
                }
                importProfileStore.save(
                    ImportProfile(mapping: columnMapping, categorySelections: resolvedSelections),
                    for: signature
                )
            }
```

- [ ] **Step 7: Call the selection prefill from ImportFlowView**

In `ImportFlowView.swift`, inside `handleColumnMappingContinue()`'s `await MainActor.run { ... }` block, after `viewModel.csvCategoryTypes = types` add:

```swift
                    viewModel.applySavedCategorySelections()
```

- [ ] **Step 8: Write the failing view-model test**

Append to `PersonalFinanceTrakerTests/TransactionListViewModelTests.swift` (matching the suite's existing setup with `MockTransactionRepository`):

```swift
@Test @MainActor func savedSelectionsPrefillOnlyValidCategories() {
    let vm = TransactionListViewModel(repo: MockTransactionRepository())
    let food = CategorySnapshot.test(name: "Food")
    vm.availableCategories = [food]
    vm.csvCategories = ["🍕 Food", "Ghost"]
    vm.importProfileStore = ImportProfileStore(
        defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    )

    // Simulate a stored profile: one valid selection, one pointing at a deleted category
    let sig = ImportProfileStore.signature(headers: ["A"], delimiter: ",")
    vm.importProfileStore.save(
        ImportProfile(
            mapping: ColumnMapping(),
            categorySelections: [
                "🍕 Food": food.id.uuidString,
                "Ghost": UUID().uuidString,
            ]
        ),
        for: sig
    )
    // Feed the saved selections through the same path applyImportProfileIfAvailable uses
    vm.setSavedCategorySelectionsForTesting(
        vm.importProfileStore.profile(for: sig)?.categorySelections
    )

    vm.applySavedCategorySelections()

    #expect(vm.categoryResolutionSelections["🍕 Food"] == food.id.uuidString)
    #expect(vm.categoryResolutionSelections["Ghost"] == nil)
}
```

This needs a test seam. In `TransactionListViewModel.swift`, below `applySavedCategorySelections()`, add:

```swift
    /// Test seam: savedCategorySelections is private because production code
    /// only sets it via applyImportProfileIfAvailable (which needs a CSVFile).
    func setSavedCategorySelectionsForTesting(_ selections: [String: String]?) {
        savedCategorySelections = selections
    }
```

- [ ] **Step 9: Run tests**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `TransactionListViewModelTests` and `ImportProfileStoreTests`.
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ImportProfileStore.swift PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVColumnMapper.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView PersonalFinanceTraker/PersonalFinanceTrakerTests
git commit -m "feat: remember import column and category mappings per file layout"
```

---

### Task 5: Daily logging reminder

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReminderService.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Components/ProfileReminderSection.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift:33-36`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift:97-101`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/ReminderSchedulerTests.swift` (new)

**Interfaces:**
- Consumes: UserDefaults keys `reminderEnabled` (Bool, default false), `reminderHour` (Int, default 21), `reminderMinute` (Int, default 0).
- Produces: `struct ReminderScheduler` with `static func fireDates(now: Date, hour: Int, minute: Int, hasLoggedToday: Bool, calendar: Calendar = .current) -> [Date]`; `@MainActor final class ReminderService` with `static let shared`, `func requestPermission() async -> Bool`, `func reschedule(hasLoggedToday: Bool)`.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTrakerTests/Utilities/ReminderSchedulerTests.swift`:

```swift
//
//  ReminderSchedulerTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct ReminderSchedulerTests {

    // Fixed "now": 2026-07-23 10:00 local
    private var now: Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 23, hour: 10, minute: 0)
        )!
    }

    @Test func schedulesSevenDaysWhenReminderTimeIsAhead() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 21, minute: 0, hasLoggedToday: false
        )
        #expect(dates.count == 7)
        let first = Calendar.current.dateComponents([.day, .hour], from: dates[0])
        #expect(first.day == 23)
        #expect(first.hour == 21)
    }

    @Test func skipsTodayWhenAlreadyLogged() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 21, minute: 0, hasLoggedToday: true
        )
        #expect(dates.count == 6)
        #expect(Calendar.current.component(.day, from: dates[0]) == 24)
    }

    @Test func skipsTodayWhenTimeHasPassed() {
        let dates = ReminderScheduler.fireDates(
            now: now, hour: 9, minute: 0, hasLoggedToday: false
        )
        #expect(dates.count == 6)
        #expect(Calendar.current.component(.day, from: dates[0]) == 24)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `ReminderSchedulerTests`.
Expected: compile FAILURE — `ReminderScheduler` not defined.

- [ ] **Step 3: Implement ReminderService**

Create `Utilities/ReminderService.swift`:

```swift
//
//  ReminderService.swift
//  PersonalFinanceTraker
//

import Foundation
import UserNotifications

/// Pure scheduling decisions, separated from UNUserNotificationCenter for tests.
struct ReminderScheduler {
    /// Next 7 daily fire dates at hour:minute. Today is skipped when the user
    /// already logged a transaction or the time has already passed.
    static func fireDates(
        now: Date,
        hour: Int,
        minute: Int,
        hasLoggedToday: Bool,
        calendar: Calendar = .current
    ) -> [Date] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                  )
            else { return nil }
            if offset == 0 && (hasLoggedToday || fire <= now) { return nil }
            return fire
        }
    }
}

@MainActor
final class ReminderService {
    static let shared = ReminderService()
    static let idPrefix = "daily-log-reminder-"
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// ponytail: 7 one-shot requests, rescheduled on scene-phase changes — no
    /// background task. If the app isn't opened for a week, reminders stop
    /// until next launch; add BGAppRefresh if that ever matters.
    func reschedule(hasLoggedToday: Bool) {
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<7).map { "\(Self.idPrefix)\($0)" }
        )
        guard UserDefaults.standard.bool(forKey: "reminderEnabled") else { return }
        let hour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 21
        let minute = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0

        let dates = ReminderScheduler.fireDates(
            now: .now, hour: hour, minute: minute, hasLoggedToday: hasLoggedToday
        )
        for (i, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Log today's spending"
            content.body = "Take 30 seconds to record what you spent today."
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            center.add(UNNotificationRequest(
                identifier: "\(Self.idPrefix)\(i)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            ))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `ReminderSchedulerTests`.
Expected: PASS (3 tests).

- [ ] **Step 5: Create the Profile section**

Create `Features/Profile/Components/ProfileReminderSection.swift`:

```swift
//
//  ProfileReminderSection.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ProfileReminderSection: View {
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 21
    @AppStorage("reminderMinute") private var reminderMinute = 0

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now
            ) ?? .now
        } set: { newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = comps.hour ?? 21
            reminderMinute = comps.minute ?? 0
            ReminderService.shared.reschedule(hasLoggedToday: false)
        }
    }

    var body: some View {
        Toggle(isOn: $reminderEnabled) {
            Label("Daily Reminder", systemImage: "bell.badge")
        }
        .onChange(of: reminderEnabled) { _, enabled in
            if enabled {
                Task {
                    let granted = await ReminderService.shared.requestPermission()
                    if granted {
                        ReminderService.shared.reschedule(hasLoggedToday: false)
                    } else {
                        reminderEnabled = false
                    }
                }
            } else {
                ReminderService.shared.reschedule(hasLoggedToday: false)
            }
        }
        if reminderEnabled {
            DatePicker(
                "Time", selection: reminderTime, displayedComponents: .hourAndMinute
            )
        }
    }
}
```

- [ ] **Step 6: Add the section to ProfileView**

In `ProfileView.swift`, after the `ProfilePayCycleSection` section (lines 33–36), add:

```swift
                    Section {
                        ProfileReminderSection()
                    }
                    .appFormSectionBackground()
```

- [ ] **Step 7: Reschedule on scene-phase changes in MainTabView**

In `MainTabView.swift`, replace the `.onChange(of: scenePhase)` block (lines 97–101) with:

```swift
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await viewModel.commitPendingDeletion() }
            }
            if phase == .active || phase == .background {
                // ponytail: in-memory check may lag a just-saved transaction by one
                // phase change; the next foreground/background pass corrects it
                let hasLoggedToday = viewModel.transactions.contains {
                    Calendar.current.isDateInToday($0.timestamp)
                }
                ReminderService.shared.reschedule(hasLoggedToday: hasLoggedToday)
            }
        }
```

- [ ] **Step 8: Build**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds.

- [ ] **Step 9: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/ReminderService.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/ReminderSchedulerTests.swift
git commit -m "feat: daily logging reminder with skip-if-logged and Profile settings"
```

---

### Task 6: App Intent quick-add

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/QuickAddService.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/App/AddTransactionIntent.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift` (reload on foreground)
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/QuickAddServiceTests.swift` (new)

**Interfaces:**
- Consumes: `TransactionActor.make(_: ModelContainer) -> TransactionActor`, `ITransactionRepository.fetchCategories() / add(_:)`, `TransactionInput(timestamp:amount:note:category:currencyCode:goalId:categoryPersistentId:)`, `CategorySnapshot` (`name`, `persistentId`), `CategorySnapshot.test(name:)` factory.
- Produces: `enum AppContainer { static let shared: ModelContainer }`; `enum QuickAddError: Error` (`invalidAmount`); `struct QuickAddService` with `static func makeInput(amount: Double, categoryName: String, isExpense: Bool, note: String, categories: [CategorySnapshot], now: Date = .now) throws -> TransactionInput`; `AddTransactionIntent`, `CategoryEntity`, `QuickAddType`, `PFTShortcuts`.

- [ ] **Step 1: Extract the shared container**

Create `App/AppContainer.swift` and MOVE the container closure plus the two static seeding helpers out of `PersonalFinanceTrakerApp.swift` (delete them there):

```swift
//
//  AppContainer.swift
//  PersonalFinanceTraker
//

import Foundation
import SwiftData

/// Single shared container — used by the app scene and by App Intents, which
/// run in-process but can't reach the App struct's instance property.
enum AppContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            TransactionModel.self,
            CategoryModel.self,
            CreditCardModel.self,
            GoalModel.self,
            HealthScoreSnapshot.self,
            DailyForecastCache.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            // Default categories are real app data (not sample data) — every user,
            // debug or release, needs them to add a transaction. Always reseed when
            // empty, including right after Delete All Data wipes CategoryModel.
            seedDefaultCategoriesIfNeeded(in: container)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @MainActor
    private static func seedDefaultCategoriesIfNeeded(in container: ModelContainer) {
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<CategoryModel>())) ?? 0
        guard count == 0 else { return }
        for category in SampleData.createSampleCategories() {
            context.insert(category)
        }
        try? context.save()
    }
}
```

In `PersonalFinanceTrakerApp.swift`:
- replace the whole `sharedModelContainer` closure property with `var sharedModelContainer: ModelContainer = AppContainer.shared`
- delete `static func seedDefaultCategoriesIfNeeded(in:)` from the private extension
- keep `seedMemberSinceDateIfNeeded()`; delete the now-unused commented `setupSampleDataIfNeeded` block and its function only if the compiler flags them (otherwise leave — out of scope).

Note: `AppContainer.shared` runs `seedDefaultCategoriesIfNeeded` which touches `mainContext`; the property is first accessed from the App struct's init on the main thread, and from intents via `MainActor`-bound seeding — the `@MainActor` annotation on the helper plus `assumeIsolated` is NOT needed because `mainContext` is only touched in that helper. If Swift 6 strict concurrency rejects calling it from the nonisolated closure, wrap the call as `MainActor.assumeIsolated { seedDefaultCategoriesIfNeeded(in: container) }`.

- [ ] **Step 2: Build to verify the refactor**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds; behavior unchanged.

- [ ] **Step 3: Write the failing QuickAddService tests**

Create `PersonalFinanceTrakerTests/Utilities/QuickAddServiceTests.swift`:

```swift
//
//  QuickAddServiceTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct QuickAddServiceTests {

    @Test func expenseIsStoredNegative() throws {
        let input = try QuickAddService.makeInput(
            amount: 12.5, categoryName: "Food", isExpense: true,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(string: "-12.5"))
    }

    @Test func incomeIsStoredPositive() throws {
        let input = try QuickAddService.makeInput(
            amount: 100, categoryName: "Salary", isExpense: false,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(100))
    }

    @Test func amountIsRoundedToTwoDecimals() throws {
        let input = try QuickAddService.makeInput(
            amount: 3.499999, categoryName: "Food", isExpense: true,
            note: "", categories: []
        )
        #expect(input.amount == Decimal(string: "-3.5"))
    }

    @Test func knownCategoryResolvesCaseInsensitively() throws {
        let food = CategorySnapshot.test(name: "Food")
        let input = try QuickAddService.makeInput(
            amount: 5, categoryName: "food", isExpense: true,
            note: "", categories: [food]
        )
        #expect(input.category == "Food")
        #expect(input.categoryPersistentId == food.persistentId)
    }

    @Test func unknownCategoryKeepsNameWithoutLink() throws {
        let input = try QuickAddService.makeInput(
            amount: 5, categoryName: "Mystery", isExpense: true,
            note: "", categories: [CategorySnapshot.test(name: "Food")]
        )
        #expect(input.category == "Mystery")
        #expect(input.categoryPersistentId == nil)
    }

    @Test func zeroAmountThrows() {
        #expect(throws: QuickAddError.self) {
            _ = try QuickAddService.makeInput(
                amount: 0, categoryName: "Food", isExpense: true,
                note: "", categories: []
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `QuickAddServiceTests`.
Expected: compile FAILURE — `QuickAddService` not defined.

- [ ] **Step 5: Implement QuickAddService**

Create `Utilities/QuickAddService.swift`:

```swift
//
//  QuickAddService.swift
//  PersonalFinanceTraker
//
//  Pure transaction-building logic for the Add Transaction App Intent,
//  separated so it's testable without AppIntents machinery.
//

import Foundation

enum QuickAddError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount: "The amount must be greater than zero."
        }
    }
}

struct QuickAddService {
    static func makeInput(
        amount: Double,
        categoryName: String,
        isExpense: Bool,
        note: String,
        categories: [CategorySnapshot],
        now: Date = .now
    ) throws -> TransactionInput {
        guard amount > 0 else { throw QuickAddError.invalidAmount }
        // Round via string to avoid Double's binary representation noise
        guard let magnitude = Decimal(
            string: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
        ) else { throw QuickAddError.invalidAmount }

        let signed = isExpense ? -magnitude : magnitude
        let match = categories.first {
            $0.name.caseInsensitiveCompare(categoryName) == .orderedSame
        }
        return TransactionInput(
            timestamp: now,
            amount: signed,
            note: note,
            category: match?.name ?? categoryName,
            currencyCode: "EUR",
            categoryPersistentId: match?.persistentId
        )
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

`mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1")` scoped to `QuickAddServiceTests`.
Expected: PASS (6 tests).

- [ ] **Step 7: Implement the intent**

Create `App/AddTransactionIntent.swift`:

```swift
//
//  AddTransactionIntent.swift
//  PersonalFinanceTraker
//

import AppIntents
import Foundation

enum QuickAddType: String, AppEnum {
    case expense, income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Type"
    static let caseDisplayRepresentations: [QuickAddType: DisplayRepresentation] = [
        .expense: "Expense",
        .income: "Income",
    ]
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    let id: String  // category name

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct CategoryEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        identifiers.map { CategoryEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        let repo = TransactionActor.make(AppContainer.shared)
        return try await repo.fetchCategories().map { CategoryEntity(id: $0.name) }
    }
}

struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static let description = IntentDescription(
        "Quickly log an expense or income without opening the app."
    )

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Type", default: .expense)
    var type: QuickAddType

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type) of \(\.$amount) in \(\.$category)") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = TransactionActor.make(AppContainer.shared)
        let categories = try await repo.fetchCategories()
        let input = try QuickAddService.makeInput(
            amount: amount,
            categoryName: category?.id ?? "Other",
            isExpense: type == .expense,
            note: note ?? "",
            categories: categories
        )
        try await repo.add(input)
        let formatted = abs(input.amount).formatted(.currency(code: "EUR"))
        return .result(dialog: "Added \(formatted) to \(input.category).")
    }
}

struct PFTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add a transaction in \(.applicationName)",
                "Log an expense in \(.applicationName)",
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle.fill"
        )
    }
}
```

- [ ] **Step 8: Reload view models on foreground**

Data saved by the intent while the app is backgrounded is invisible to the cached view models. In `MainTabView.swift`, inside the `.onChange(of: scenePhase)` block (as modified in Task 5), add a foreground reload:

```swift
            if phase == .active {
                // Data may have changed outside the UI (App Intent quick-add)
                dashboardViewModel.reload()
                viewModel.reload()
            }
```

- [ ] **Step 9: Build and run full test suite**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`, then `mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`.
Expected: build succeeds, all tests pass.

- [ ] **Step 10: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/App PersonalFinanceTraker/PersonalFinanceTraker/Utilities/QuickAddService.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/QuickAddServiceTests.swift
git commit -m "feat: Add Transaction App Intent with Siri/Shortcuts support"
```

---

### Task 7: Final verification

**Files:** none new.

- [ ] **Step 1: Run the full test suite**

`ToolSearch` query `select:mcp__xcode__RunAllTests,mcp__xcode__GetBuildLog`, then `mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")`.
Expected: ALL tests pass. On failure, `mcp__xcode__GetBuildLog(tabIdentifier: "windowtab1")` for details — fix before proceeding.

- [ ] **Step 2: Update the knowledge graph**

```bash
graphify update .
```

- [ ] **Step 3: Manual smoke checklist (run app in Simulator via Xcode)**

- Dashboard shows the anomaly callout when a spike exists; dismiss hides it.
- Profile → Daily Reminder toggle prompts for notification permission.
- Import the real test file (`~/Documents/2026-05-21.csv`), complete the wizard, re-import the same file: both wizard steps arrive prefilled.
- In the Shortcuts app, "Add Transaction" appears; running it with amount + category saves a transaction that shows in Activity after foregrounding the app.
