# Entitlements Bootstrap + Safe-to-Spend Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap the App Group entitlement, add a WidgetKit extension target, and ship a home-screen widget that shows "safe to spend until payday" — refreshed whenever a transaction (or recurring rule) mutates.

**Architecture:** The app target computes a 7-day-forward `SafeToSpendSnapshot` after every transaction-affecting mutation on `TransactionActor` and writes it as JSON into a shared App Group container. The widget extension never touches SwiftData or business-logic services — its `TimelineProvider` only reads that JSON. A small shared file (`SafeToSpendSnapshot.swift`) holds the Codable model plus the pure `amount(for:from:)` lookup, so both targets agree on the format and the "missing/undecodable/exhausted → nil" rule is defined once and unit-testable from the app target.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, WidgetKit, Swift Testing (`@Test`/`#expect`), Xcode 16 file-system-synchronized groups.

## Global Constraints

- Bundle identifier: `rizzoG99.PersonalFinanceTraker`; development team: `9T6Z73ZMFU`.
- App Group identifier to create/use: `group.rizzoG99.PersonalFinanceTraker`.
- **No CloudKit entitlement in this plan** — App Group only. CloudKit is added later, when iCloud sync is actually scoped.
- Widget shows **safe-to-spend until payday** as its headline number (not plain balance).
- Snapshot window is **exactly 7 days forward** (today + 6 more days).
- Missing, undecodable, or exhausted (date past the last cached day) snapshot lookup → widget renders a neutral empty state, **never** a stale/last-known number.
- Snapshot refresh is triggered from exactly these `TransactionActor` methods, and no others: `add`, `addBatch`, `update`, `delete`, `addRecurrenceRule`, `updateRecurrenceRule`, `deleteOccurrences`, `materializeOccurrences`, `deleteAllTransactions`, `deleteAllRecurrenceRules`. **Amended during Task 4 execution** (with explicit human sign-off): the code originally underlying this plan drifted from `main` before Task 4 ran and gained `deleteAllTransactions`/`deleteAllRecurrenceRules` (the PIN-confirmed "Delete All Data" wipe feature). Skipping them would leave the widget showing a stale, wrong number after a full wipe — the worst-case staleness scenario this design otherwise guards against — so they were added to the trigger list. `closeRecurrenceRule` and `saveForecastCache` remain correctly excluded (see Task 4 below).
- **Shared formatting file added mid-implementation, not originally planned:** `PersonalFinanceTraker/Shared/DecimalFormatting.swift` was created during Task 5 to hold `Decimal.formattedEUR`/`formattedEURCompact` (moved unchanged from `CurrencyService.swift`), because the widget extension target cannot import the app-only `CurrencyService.swift` and the widget view's sample code depends on `formattedEURCompact`. This follows the same "small shared source file" pattern the plan already used for `SafeToSpendSnapshot.swift` — no app-facing formatting behavior changed, only the file's location. Reviewed and approved in Task 5.
- Tests use Swift Testing (`@Test`, `#expect`), `@testable import PersonalFinanceTraker` — NOT XCTest.
- **NEVER run `xcodebuild` in Bash.** Build/test verification must go through the Xcode MCP tools: load their schema first with `ToolSearch(query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests")`, then call with `tabIdentifier: "windowtab1"`.
- This project uses Xcode 16 `PBXFileSystemSynchronizedRootGroup`s: any `.swift` file placed inside a target's synced folder is auto-included in that target. A file needed by a *second* target (the widget extension) needs its Target Membership checkbox ticked manually in Xcode's File Inspector — this is a normal, well-trodden operation, not a project restructure.
- Existing convention: expenses are stored as **negative** `Decimal`, income as positive; `CurrencyService.convertToBase` sums correctly across mixed signs without special-casing.
- Reuse existing test factories: `TransactionSnapshot.test(...)` and `RecurrenceRuleSnapshot.test(...)` in `PersonalFinanceTrakerTests/Mocks/TransactionSnapshotFactory.swift`.

---

### Task 1: Add App Group entitlement + create the WidgetKit extension target (manual Xcode step)

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/PersonalFinanceTraker.entitlements`
- Create (via Xcode's "New Target" flow): `PersonalFinanceTraker/SafeToSpendWidget/` target folder, `SafeToSpendWidgetExtension.entitlements`, default `Info.plist`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: an App Group container both targets can read/write via `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.rizzoG99.PersonalFinanceTraker")`; a new target named `SafeToSpendWidgetExtension` that later tasks add files to.

This task can't be done by editing Swift files — a new Xcode target is project-file surgery that the Xcode MCP tools don't expose (they only build/test/list — no target creation). Do it in the Xcode GUI:

- [ ] **Step 1: Add the App Group capability to the main app target**

  Open `PersonalFinanceTraker.xcodeproj` in Xcode. Select the `PersonalFinanceTraker` target → **Signing & Capabilities** → **+ Capability** → **App Groups**. Click **+** under App Groups and add `group.rizzoG99.PersonalFinanceTraker`. Xcode writes this into `PersonalFinanceTraker.entitlements` automatically — verify it now contains:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.application-groups</key>
      <array>
          <string>group.rizzoG99.PersonalFinanceTraker</string>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Create the widget extension target**

  File → New → Target… → **Widget Extension**. Product Name: `SafeToSpendWidget`. Uncheck "Include Live Activity" and "Include Configuration App Intent" (not needed for a static timeline widget). Team: `9T6Z73ZMFU`. When Xcode asks to activate the new scheme, choose "Activate".

  This creates a `SafeToSpendWidget` folder (synced root group) with a default `SafeToSpendWidget.swift`, `SafeToSpendWidgetBundle.swift` (or similar auto-generated names — these get replaced in Task 5), an `Info.plist`, and its own entitlements file.

- [ ] **Step 3: Add the App Group capability to the widget extension target**

  Select the new `SafeToSpendWidgetExtension` target → **Signing & Capabilities** → **+ Capability** → **App Groups** → check the same `group.rizzoG99.PersonalFinanceTraker` (it should now appear as a checkbox since it exists from Step 1 — don't create a second group).

- [ ] **Step 4: Build to confirm both targets compile and are signed**

  Load the Xcode MCP tools and build:

  ```
  ToolSearch(query: "select:mcp__xcode__BuildProject")
  mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
  ```

  Expected: build succeeds for both the app scheme and the new widget extension scheme (no signing errors about the App Group).

- [ ] **Step 5: Commit**

  ```bash
  git add PersonalFinanceTraker/PersonalFinanceTraker/PersonalFinanceTraker.entitlements PersonalFinanceTraker/SafeToSpendWidget PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj
  git commit -m "chore: bootstrap App Group entitlement and SafeToSpendWidget extension target"
  ```

---

### Task 2: Shared `AppGroup` identifier + `SafeToSpendSnapshot` model with pure lookup

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/AppGroup.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/SafeToSpendSnapshot.swift`
- Test: `PersonalFinanceTrakerTests/Models/SafeToSpendSnapshotTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `enum AppGroup { static let identifier: String }`; `enum SafeToSpendWidgetKind { static let name: String }`; `struct SafeToSpendDayValue: Codable, Sendable, Equatable { let date: Date; let amount: Decimal }`; `struct SafeToSpendSnapshot: Codable, Sendable, Equatable { let generatedAt: Date; let currencyCode: String; let days: [SafeToSpendDayValue] }` with `func write() throws`, `static func load() -> SafeToSpendSnapshot?`, and `static func amount(for date: Date, from snapshot: SafeToSpendSnapshot?, calendar: Calendar = .current) -> Decimal?`. Later tasks (3, 4, 5) depend on these exact names and signatures.

- [ ] **Step 1: Write the failing tests**

  ```swift
  //
  //  SafeToSpendSnapshotTests.swift
  //  PersonalFinanceTrakerTests
  //

  import Foundation
  import Testing
  @testable import PersonalFinanceTraker

  @Suite("SafeToSpendSnapshot")
  struct SafeToSpendSnapshotTests {

      private func day(_ offset: Int, from base: Date = .now, calendar: Calendar = .current) -> Date {
          calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: base)!)
      }

      @Test func amountReturnsMatchingDayValue() {
          let today = day(0)
          let snapshot = SafeToSpendSnapshot(
              generatedAt: today,
              currencyCode: "EUR",
              days: [
                  SafeToSpendDayValue(date: today, amount: 120),
                  SafeToSpendDayValue(date: day(1), amount: 100)
              ]
          )
          #expect(SafeToSpendSnapshot.amount(for: day(1), from: snapshot) == 100)
      }

      @Test func amountReturnsNilWhenSnapshotIsMissing() {
          #expect(SafeToSpendSnapshot.amount(for: day(0), from: nil) == nil)
      }

      @Test func amountReturnsNilWhenDateIsPastLastCachedDay() {
          let today = day(0)
          let snapshot = SafeToSpendSnapshot(
              generatedAt: today,
              currencyCode: "EUR",
              days: [SafeToSpendDayValue(date: today, amount: 120)]
          )
          // Requesting day 6, but the snapshot only has day 0 cached — exhausted.
          #expect(SafeToSpendSnapshot.amount(for: day(6), from: snapshot) == nil)
      }

      @Test func roundTripsThroughJSON() throws {
          let today = day(0)
          let snapshot = SafeToSpendSnapshot(
              generatedAt: today,
              currencyCode: "EUR",
              days: (0..<7).map { SafeToSpendDayValue(date: day($0), amount: Decimal(100 - $0 * 5)) }
          )
          let data = try JSONEncoder().encode(snapshot)
          let decoded = try JSONDecoder().decode(SafeToSpendSnapshot.self, from: data)
          #expect(decoded == snapshot)
      }
  }
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  ```
  ToolSearch(query: "select:mcp__xcode__RunSomeTests")
  mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/SafeToSpendSnapshotTests"])
  ```

  Expected: FAIL — `SafeToSpendSnapshot`, `SafeToSpendDayValue` not defined.

- [ ] **Step 3: Write `AppGroup.swift`**

  ```swift
  //
  //  AppGroup.swift
  //  PersonalFinanceTraker
  //

  import Foundation

  enum AppGroup {
      static let identifier = "group.rizzoG99.PersonalFinanceTraker"
  }

  enum SafeToSpendWidgetKind {
      static let name = "SafeToSpendWidget"
  }
  ```

- [ ] **Step 4: Write `SafeToSpendSnapshot.swift`**

  ```swift
  //
  //  SafeToSpendSnapshot.swift
  //  PersonalFinanceTraker
  //
  //  Shared with the SafeToSpendWidgetExtension target (Target Membership set manually
  //  in Xcode — see docs/superpowers/plans/2026-08-03-widget-entitlements-plan.md Task 2).
  //

  import Foundation

  struct SafeToSpendDayValue: Codable, Sendable, Equatable {
      let date: Date
      let amount: Decimal
  }

  struct SafeToSpendSnapshot: Codable, Sendable, Equatable {
      let generatedAt: Date
      let currencyCode: String
      let days: [SafeToSpendDayValue]

      private static let fileName = "safe_to_spend_snapshot.json"

      private static func containerURL() -> URL? {
          FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
      }

      func write() throws {
          guard let dir = Self.containerURL() else {
              throw SafeToSpendSnapshotError.noContainer
          }
          let url = dir.appendingPathComponent(Self.fileName)
          let data = try JSONEncoder().encode(self)
          try data.write(to: url, options: .atomic)
      }

      static func load() -> SafeToSpendSnapshot? {
          guard let dir = containerURL() else { return nil }
          let url = dir.appendingPathComponent(fileName)
          guard let data = try? Data(contentsOf: url) else { return nil }
          return try? JSONDecoder().decode(SafeToSpendSnapshot.self, from: data)
      }

      /// Returns the safe-to-spend amount for `date`, or nil if the snapshot is missing,
      /// undecodable, or `date` falls outside the cached days — callers must render the
      /// neutral empty state in every one of those cases, never the last known value.
      static func amount(for date: Date, from snapshot: SafeToSpendSnapshot?, calendar: Calendar = .current) -> Decimal? {
          guard let snapshot else { return nil }
          let day = calendar.startOfDay(for: date)
          return snapshot.days.first { calendar.isDate($0.date, inSameDayAs: day) }?.amount
      }
  }

  enum SafeToSpendSnapshotError: Error {
      case noContainer
  }
  ```

- [ ] **Step 5: Run the tests to verify they pass**

  ```
  mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/SafeToSpendSnapshotTests"])
  ```

  Expected: PASS (4/4).

- [ ] **Step 6: Set Target Membership so the widget extension can also compile this file**

  In Xcode's File Inspector (right-hand panel) for both `AppGroup.swift` and `SafeToSpendSnapshot.swift`, check the box for `SafeToSpendWidgetExtension` under Target Membership (in addition to the already-checked `PersonalFinanceTraker` app target).

- [ ] **Step 7: Build both targets to confirm the shared files compile in the extension too**

  ```
  mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
  ```

  Expected: build succeeds for both schemes.

- [ ] **Step 8: Commit**

  ```bash
  git add PersonalFinanceTraker/PersonalFinanceTraker/Models/AppGroup.swift PersonalFinanceTraker/PersonalFinanceTraker/Models/SafeToSpendSnapshot.swift PersonalFinanceTrakerTests/Models/SafeToSpendSnapshotTests.swift PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj
  git commit -m "feat: add shared SafeToSpendSnapshot model with pure day-lookup"
  ```

---

### Task 3: `SafeToSpendSnapshotBuilder` — pure computation from transactions + recurring rules

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SafeToSpendSnapshotBuilder.swift`
- Test: `PersonalFinanceTrakerTests/Utilities/SafeToSpendSnapshotBuilderTests.swift`

**Interfaces:**
- Consumes: `SafeToSpendSnapshot`/`SafeToSpendDayValue` (Task 2), `TransactionSnapshot`, `RecurrenceRuleSnapshot`, `RecurrenceOccurrenceCalculator.occurrenceDates(frequency:interval:startDate:ruleEndDate:since:through:calendar:)`, `PayCycleService.currentFinancialMonth(startDay:calendar:)`, `CurrencyService.convertToBase(_:from:)`.
- Produces: `enum SafeToSpendSnapshotBuilder { static func build(transactions: [TransactionSnapshot], activeRules: [RecurrenceRuleSnapshot], payCycleStartDay: Int, currencyService: CurrencyService, now: Date = .now, calendar: Calendar = .current, forwardDays: Int = 7) -> SafeToSpendSnapshot }`. Task 4 calls this exact signature.

- [ ] **Step 1: Write the failing tests**

  ```swift
  //
  //  SafeToSpendSnapshotBuilderTests.swift
  //  PersonalFinanceTrakerTests
  //

  import Foundation
  import Testing
  @testable import PersonalFinanceTraker

  @Suite("SafeToSpendSnapshotBuilder")
  struct SafeToSpendSnapshotBuilderTests {

      private let calendar = Calendar.current
      private let currencyService = CurrencyService(defaults: UserDefaults(suiteName: "SafeToSpendSnapshotBuilderTests")!)

      private func daysAgo(_ n: Int, from now: Date) -> Date {
          calendar.date(byAdding: .day, value: -n, to: now)!
      }

      @Test func todaysAmountIsNetOfThisPayCycleWithNoRecurringRules() {
          let now = Date.now
          let transactions = [
              TransactionSnapshot.test(timestamp: now, amount: 2000, category: "Salary"),
              TransactionSnapshot.test(timestamp: daysAgo(1, from: now), amount: -300, category: "Rent")
          ]
          let snapshot = SafeToSpendSnapshotBuilder.build(
              transactions: transactions,
              activeRules: [],
              payCycleStartDay: 1,
              currencyService: currencyService,
              now: now,
              calendar: calendar
          )
          #expect(snapshot.days.count == 7)
          #expect(snapshot.days[0].amount == 1700)
      }

      @Test func futureRecurringExpenseReducesLaterDaysNotToday() {
          let now = Date.now
          let inThreeDays = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
          let rule = RecurrenceRuleSnapshot.test(
              frequency: .monthly,
              interval: 1,
              startDate: inThreeDays,
              lastMaterializedDate: daysAgo(30, from: now),
              amount: -50,
              category: "Subscription"
          )
          let transactions = [TransactionSnapshot.test(timestamp: now, amount: 500, category: "Salary")]
          let snapshot = SafeToSpendSnapshotBuilder.build(
              transactions: transactions,
              activeRules: [rule],
              payCycleStartDay: 1,
              currencyService: currencyService,
              now: now,
              calendar: calendar
          )
          #expect(snapshot.days[0].amount == 500)       // today: rule hasn't hit yet
          #expect(snapshot.days[2].amount == 500)        // day before the occurrence: still untouched
          #expect(snapshot.days[3].amount == 450)        // occurrence day: committed expense applied
          #expect(snapshot.days[6].amount == 450)        // stays applied through the rest of the window
      }

      @Test func producesExactlySevenDaysStartingToday() {
          let now = Date.now
          let snapshot = SafeToSpendSnapshotBuilder.build(
              transactions: [],
              activeRules: [],
              payCycleStartDay: 1,
              currencyService: currencyService,
              now: now,
              calendar: calendar
          )
          #expect(snapshot.days.count == 7)
          #expect(calendar.isDate(snapshot.days[0].date, inSameDayAs: now))
          let expectedLastDay = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now))!
          #expect(calendar.isDate(snapshot.days[6].date, inSameDayAs: expectedLastDay))
      }
  }
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  ```
  mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/SafeToSpendSnapshotBuilderTests"])
  ```

  Expected: FAIL — `SafeToSpendSnapshotBuilder` not defined.

- [ ] **Step 3: Write the implementation**

  ```swift
  //
  //  SafeToSpendSnapshotBuilder.swift
  //  PersonalFinanceTraker
  //

  import Foundation

  enum SafeToSpendSnapshotBuilder {
      /// Builds a 7-day-forward safe-to-spend projection. Day 0 (today) is the current
      /// pay-cycle net (income - expenses so far this cycle, via `TransactionSnapshot`s that
      /// already include anything materialized). Days 1-6 subtract/add committed amounts from
      /// active `RecurrenceRule`s whose occurrence date falls in that window — those haven't
      /// been materialized into real transactions yet (materialization only runs through
      /// "today"), so counting them here without double-counting is safe.
      static func build(
          transactions: [TransactionSnapshot],
          activeRules: [RecurrenceRuleSnapshot],
          payCycleStartDay: Int,
          currencyService: CurrencyService,
          now: Date = .now,
          calendar: Calendar = .current,
          forwardDays: Int = 7
      ) -> SafeToSpendSnapshot {
          let (cycleStart, cycleEnd) = PayCycleService.currentFinancialMonth(startDay: payCycleStartDay, calendar: calendar)

          let netSoFar = transactions
              .filter { $0.timestamp >= cycleStart && $0.timestamp <= cycleEnd }
              .reduce(Decimal(0)) { $0 + currencyService.convertToBase($1.amount, from: $1.currencyCode) }

          let today = calendar.startOfDay(for: now)

          let days: [SafeToSpendDayValue] = (0..<forwardDays).map { offset in
              let dayDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
              guard offset > 0 else {
                  return SafeToSpendDayValue(date: dayDate, amount: netSoFar)
              }
              let committed = activeRules.reduce(Decimal(0)) { total, rule in
                  let occurrences = RecurrenceOccurrenceCalculator.occurrenceDates(
                      frequency: rule.frequency,
                      interval: rule.interval,
                      startDate: rule.startDate,
                      ruleEndDate: rule.endDate,
                      since: today,
                      through: dayDate,
                      calendar: calendar
                  )
                  guard !occurrences.isEmpty else { return total }
                  return total + Decimal(occurrences.count) * currencyService.convertToBase(rule.amount, from: rule.currencyCode)
              }
              return SafeToSpendDayValue(date: dayDate, amount: netSoFar + committed)
          }

          return SafeToSpendSnapshot(generatedAt: now, currencyCode: currencyService.baseCurrency, days: days)
      }
  }
  ```

- [ ] **Step 4: Run the tests to verify they pass**

  ```
  mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["PersonalFinanceTrakerTests/SafeToSpendSnapshotBuilderTests"])
  ```

  Expected: PASS (3/3).

- [ ] **Step 5: Commit**

  ```bash
  git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/SafeToSpendSnapshotBuilder.swift PersonalFinanceTrakerTests/Utilities/SafeToSpendSnapshotBuilderTests.swift
  git commit -m "feat: add SafeToSpendSnapshotBuilder pure computation"
  ```

---

### Task 4: Wire the snapshot refresh into `TransactionActor`'s mutation choke points

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`

**Interfaces:**
- Consumes: `SafeToSpendSnapshotBuilder.build(...)` (Task 3), `SafeToSpendSnapshot.write()` (Task 2), `AppSettings.storedStartDay` (existing `static var`, `@MainActor`-isolated — call with `await`), `CurrencyService()` (existing, cheap synchronous init), `WidgetCenter.shared.reloadTimelines(ofKind:)` (WidgetKit).
- Produces: nothing new for later tasks — this is the last app-side wiring point. Task 5/6 (widget extension) only depend on `SafeToSpendSnapshot.load()` and `SafeToSpendWidgetKind.name`, both already defined in Task 2.

No new automated test here: this task's job is only to call already-tested code (`SafeToSpendSnapshotBuilder`, already covered in Task 3) from eight existing methods, plus call `WidgetCenter.reloadTimelines` and `snapshot.write()`, which need a real App Group container / real widget host to observe — that's covered by the manual smoke test in Task 6, not a unit test. This matches the design spec's own testing section (only the builder and the day-lookup needed dedicated tests).

- [ ] **Step 1: Add the private refresh helper and its import**

  In `TransactionActor.swift`, add `import WidgetKit` alongside the existing imports, and add this private method inside the `actor TransactionActor` body (place it right after `saveForecastCache`, before the closing `}` of the actor):

  ```swift
  // MARK: Safe-to-spend widget refresh

  /// Single place that recomputes and republishes the safe-to-spend snapshot. Called from
  /// every mutation method that can change future spending (see call sites below) — NOT from
  /// saveForecastCache, whose only caller (InsightsViewModel.computeForecast) fires on Insights
  /// recompute, not on a logged transaction, which would leave the widget stale right when
  /// freshness matters most.
  private func refreshSafeToSpendWidget() async {
      guard let transactions = try? await fetchAll(),
            let rules = try? await fetchActiveRecurrenceRules() else { return }
      let payCycleStartDay = await AppSettings.storedStartDay
      let snapshot = SafeToSpendSnapshotBuilder.build(
          transactions: transactions,
          activeRules: rules,
          payCycleStartDay: payCycleStartDay,
          currencyService: CurrencyService()
      )
      try? snapshot.write()
      WidgetCenter.shared.reloadTimelines(ofKind: SafeToSpendWidgetKind.name)
  }
  ```

- [ ] **Step 2: Call it from `add`**

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
      await refreshSafeToSpendWidget()
  }
  ```

- [ ] **Step 3: Call it from `addBatch`, `delete`, `update`**

  Add `await refreshSafeToSpendWidget()` as the last line of each method body, immediately after the existing `try modelContext.save()`:

  ```swift
  func addBatch(_ inputs: [TransactionInput]) async throws {
      // Insert all models first, then save once to minimize round-trips
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
      await refreshSafeToSpendWidget()
  }

  func delete(id: PersistentIdentifier) async throws {
      guard let model = modelContext.model(for: id) as? TransactionModel else { return }
      modelContext.delete(model)
      try modelContext.save()
      await refreshSafeToSpendWidget()
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
      await refreshSafeToSpendWidget()
  }
  ```

- [ ] **Step 4: Call it from `addRecurrenceRule`, `updateRecurrenceRule`, `deleteOccurrences`, `materializeOccurrences`**

  Same pattern — add `await refreshSafeToSpendWidget()` as the last line of each, after the existing `try modelContext.save()`:

  ```swift
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
      await refreshSafeToSpendWidget()
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
      await refreshSafeToSpendWidget()
  }

  func deleteOccurrences(recurrenceRuleId: UUID, from cutoffDate: Date) async throws {
      let rows = try modelContext.fetch(FetchDescriptor<TransactionModel>(
          predicate: #Predicate { $0.recurrenceRuleId == recurrenceRuleId && $0.timestamp >= cutoffDate }
      ))
      rows.forEach { modelContext.delete($0) }

      var ruleDesc = FetchDescriptor<RecurrenceRule>(predicate: #Predicate { $0.id == recurrenceRuleId })
      ruleDesc.fetchLimit = 1
      if let rule = try modelContext.fetch(ruleDesc).first {
          rule.lastMaterializedDate = Calendar.current.date(byAdding: .day, value: -1, to: cutoffDate)
      }
      try modelContext.save()
      await refreshSafeToSpendWidget()
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
      await refreshSafeToSpendWidget()
  }
  ```

  Leave `closeRecurrenceRule` untouched — it only sets an end date and doesn't alter any existing transaction, so it doesn't need to trigger a refresh.

- [ ] **Step 5: Run the full test suite to confirm nothing regressed**

  ```
  ToolSearch(query: "select:mcp__xcode__RunAllTests")
  mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
  ```

  Expected: all existing tests still pass (the new `await refreshSafeToSpendWidget()` calls are best-effort/`try?`-guarded internally and silently no-op when there's no App Group container available, e.g. under plain unit tests, so no existing test behavior changes).

- [ ] **Step 6: Commit**

  ```bash
  git add PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift
  git commit -m "feat: refresh safe-to-spend widget snapshot from TransactionActor mutations"
  ```

---

### Task 5: Widget extension — entry, provider, view, and widget/bundle registration

**Files:**
- Modify/Replace: the auto-generated widget files under `PersonalFinanceTraker/SafeToSpendWidget/` from Task 1 Step 2 (exact filenames vary by Xcode version — replace whatever Xcode generated with the files below; delete the generated `AppIntent`/`ConfigurationAppIntent`-related file if present, since this is a static, non-configurable widget)
- Create: `PersonalFinanceTraker/SafeToSpendWidget/SafeToSpendEntry.swift`
- Create: `PersonalFinanceTraker/SafeToSpendWidget/SafeToSpendProvider.swift`
- Create: `PersonalFinanceTraker/SafeToSpendWidget/SafeToSpendWidgetView.swift`
- Create: `PersonalFinanceTraker/SafeToSpendWidget/SafeToSpendWidget.swift`

**Interfaces:**
- Consumes: `SafeToSpendSnapshot.load()`, `SafeToSpendSnapshot.amount(for:from:)`, `SafeToSpendWidgetKind.name` (all from Task 2, shared into this target).
- Produces: the `@main` widget entry point for the `SafeToSpendWidgetExtension` target. Nothing later depends on this task.

No dedicated test target for the widget extension — its only logic (mapping a date to an amount, and treating "not found" as the empty state) is the already-tested `SafeToSpendSnapshot.amount(for:from:)` pure function from Task 2. This task is UI/glue code, verified by the manual smoke test in Task 6.

- [ ] **Step 1: Write `SafeToSpendEntry.swift`**

  ```swift
  //
  //  SafeToSpendEntry.swift
  //  SafeToSpendWidget
  //

  import WidgetKit

  struct SafeToSpendEntry: TimelineEntry {
      let date: Date
      let amount: Decimal?
      let currencyCode: String
  }
  ```

- [ ] **Step 2: Write `SafeToSpendProvider.swift`**

  ```swift
  //
  //  SafeToSpendProvider.swift
  //  SafeToSpendWidget
  //

  import WidgetKit
  import Foundation

  struct SafeToSpendProvider: TimelineProvider {
      func placeholder(in context: Context) -> SafeToSpendEntry {
          SafeToSpendEntry(date: .now, amount: 120, currencyCode: "EUR")
      }

      func getSnapshot(in context: Context, completion: @escaping (SafeToSpendEntry) -> Void) {
          completion(makeEntry(for: .now))
      }

      func getTimeline(in context: Context, completion: @escaping (Timeline<SafeToSpendEntry>) -> Void) {
          let calendar = Calendar.current
          let now = Date.now
          let entries = (0..<7).map { offset -> SafeToSpendEntry in
              let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
              return makeEntry(for: date)
          }
          // Periodic backstop: reload every few hours even without an app-triggered
          // WidgetCenter.reloadTimelines call, so day-rollover still shows the right
          // pre-computed number.
          let nextRefresh = calendar.date(byAdding: .hour, value: 4, to: now) ?? now
          completion(Timeline(entries: entries, policy: .after(nextRefresh)))
      }

      private func makeEntry(for date: Date) -> SafeToSpendEntry {
          let snapshot = SafeToSpendSnapshot.load()
          let amount = SafeToSpendSnapshot.amount(for: date, from: snapshot)
          return SafeToSpendEntry(date: date, amount: amount, currencyCode: snapshot?.currencyCode ?? "EUR")
      }
  }
  ```

- [ ] **Step 3: Write `SafeToSpendWidgetView.swift`**

  ```swift
  //
  //  SafeToSpendWidgetView.swift
  //  SafeToSpendWidget
  //

  import SwiftUI
  import WidgetKit

  struct SafeToSpendWidgetView: View {
      let entry: SafeToSpendEntry

      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              Text("Safe to spend")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              if let amount = entry.amount {
                  Text(amount.formattedEURCompact(currency: entry.currencyCode))
                      .font(.title2.bold())
                      .minimumScaleFactor(0.7)
              } else {
                  Text("Open the app")
                      .font(.title3.bold())
                      .foregroundStyle(.secondary)
              }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .padding()
          .containerBackground(.fill.tertiary, for: .widget)
      }
  }
  ```

- [ ] **Step 4: Write `SafeToSpendWidget.swift`**

  ```swift
  //
  //  SafeToSpendWidget.swift
  //  SafeToSpendWidget
  //

  import SwiftUI
  import WidgetKit

  struct SafeToSpendWidget: Widget {
      var body: some WidgetConfiguration {
          StaticConfiguration(kind: SafeToSpendWidgetKind.name, provider: SafeToSpendProvider()) { entry in
              SafeToSpendWidgetView(entry: entry)
          }
          .configurationDisplayName("Safe to Spend")
          .description("Shows how much you can safely spend until your next payday.")
          .supportedFamilies([.systemSmall])
      }
  }

  @main
  struct SafeToSpendWidgetBundle: WidgetBundle {
      var body: some Widget {
          SafeToSpendWidget()
      }
  }
  ```

  Delete any other auto-generated widget/bundle file from Task 1 Step 2 so there's exactly one `@main` entry point in this target.

- [ ] **Step 5: Build the widget extension scheme**

  ```
  mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
  ```

  Expected: both schemes build with no errors (in particular, no "duplicate @main" or missing-symbol errors from the deleted auto-generated files).

- [ ] **Step 6: Commit**

  ```bash
  git add PersonalFinanceTraker/SafeToSpendWidget
  git commit -m "feat: implement SafeToSpendWidget timeline provider and view"
  ```

---

### Task 6: Manual smoke test — verify the widget end-to-end in the simulator

**Files:** none (verification only).

**Interfaces:** none — this task consumes everything from Tasks 1-5 and produces nothing further.

- [ ] **Step 1: Run the app in the simulator**

  ```
  ToolSearch(query: "select:mcp__xcode__BuildProject")
  mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
  ```

  Then launch the app from Xcode (Run) on a simulator that supports widgets (any current iOS 17+ simulator).

- [ ] **Step 2: Verify the empty state before any transaction exists**

  On first install (or after "Delete All Data"), long-press the simulator home screen → **+** → search "Safe to Spend" → add the small widget. Confirm it shows **"Open the app"**, not a number or a crash — this exercises the "missing snapshot" path from `SafeToSpendSnapshot.amount(for:from:)`.

- [ ] **Step 3: Log a transaction and verify the widget updates**

  In the app, add an income transaction (e.g. +€2000, category "Salary"). Return to the home screen. The widget should update within a few seconds (via `WidgetCenter.reloadTimelines`, no manual widget refresh needed) to show the new safe-to-spend figure.

- [ ] **Step 4: Verify a recurring rule shifts a future day's figure**

  If recurring transactions are available in this build, add a monthly recurring expense starting a few days from now. Confirm (by temporarily lowering `forwardDays` for a manual check, or by trusting the already-passing `SafeToSpendSnapshotBuilderTests` from Task 3) that the committed amount is reflected — this step is a sanity check of the wiring, not a re-verification of the math, which is already unit-tested.

- [ ] **Step 5: Confirm no regressions in the full test suite**

  ```
  mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
  ```

  Expected: all tests green.

- [ ] **Step 6: Commit any final fixups found during the smoke test**

  If Step 2-4 surfaced a bug, fix it, re-run the relevant test(s) from Task 2/3, then:

  ```bash
  git add -A
  git commit -m "fix: address issues found in safe-to-spend widget smoke test"
  ```

  If nothing needed fixing, skip this step — there's nothing to commit.
