# Auto-Backup & Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Periodically export all transactions and recurrence rules as plaintext JSON to the app's iCloud Drive ubiquity container, so a user who accidentally deletes the app can restore their data; add a manual, confirmed, wipe-and-replace restore flow.

**Architecture:** A pure `BackupService` (injectable storage) writes/reads/rotates timestamped JSON files in an iCloud Drive container. A `BackupScheduler` runs on app foreground, gated by a 24h staleness check and an empty-store guard baked into `BackupService` itself. `RestoreService` decodes the newest backup and performs a wipe-and-replace via two new repository methods. UI lives in the existing Profile DATA section.

**Tech Stack:** Foundation (`FileManager`, `JSONEncoder`/`JSONDecoder`, atomic file writes), SwiftData (`ModelActor`), SwiftUI (`scenePhase`). No new dependencies — CryptoKit/Security are already imported elsewhere in the project but are **not** used here (see spec's rejection of app-layer encryption).

## Global Constraints

- No new third-party dependencies.
- Swift Testing (`@Test`, `#expect`), not XCTest; `@testable import PersonalFinanceTraker` — copy the style in `TransactionActorRecurrenceTests.swift` and `EditAddTransactionViewModelTests.swift` exactly.
- **Never run `xcodebuild` or any `mcp__xcode__*` tool name in Bash.** Build and test verification must go through `ToolSearch` (`query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"`) then the MCP tool call itself with `tabIdentifier: "windowtab1"`.
- Amounts are `Decimal`, expenses negative — backup/restore is a pass-through, no sign conversion.
- Currency is `currencyCode: String` per record, no hardcoding — carry it through unchanged.
- New optional fields on existing structs must have default values so existing call sites don't break (e.g. `RecurrenceRuleInput`'s new `endDate`/`lastMaterializedDate` params default to `nil`, matching today's behavior for every existing caller).
- Directory typo is intentional and must be preserved: `PersonalFinanceTraker` (missing the second 'c').

---

### Task 1: iCloud Drive entitlement + `RecurrenceFrequency` Codable conformance

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/PersonalFinanceTraker.entitlements`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceFrequency.swift`

**Interfaces:**
- Produces: `RecurrenceFrequency: Codable` (needed by `BackupRecurrenceRule` in Task 3), and a working iCloud Drive ubiquity container (needed by `FileManagerBackupStorage` in Task 4).

This is pure configuration and a zero-logic protocol conformance (Swift auto-synthesizes `Codable` for a `String`-raw-value enum) — there's no branch or loop to unit-test, so verification is a build, not a test.

- [ ] **Step 1: Add the iCloud Drive container + service to the entitlements file**

Current file:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array/>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
</dict>
</plist>
```

Change to:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.$(CFBundleIdentifier)</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
		<string>CloudDocuments</string>
	</array>
</dict>
</plist>
```

`CloudDocuments` is what makes `FileManager.default.url(forUbiquityContainerIdentifier:)` resolve to a real container; `CloudKit` is left in place since it was already there for something else in the project.

- [ ] **Step 2: Add `Codable` to `RecurrenceFrequency`**

Find in `Models/RecurrenceFrequency.swift`:
```swift
enum RecurrenceFrequency: String, CaseIterable, Sendable {
```

Change to:
```swift
enum RecurrenceFrequency: String, CaseIterable, Sendable, Codable {
```

- [ ] **Step 3: Build to verify no regressions**

Use `ToolSearch` with `query: "select:mcp__xcode__BuildProject"`, then call `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/PersonalFinanceTraker.entitlements" "PersonalFinanceTraker/PersonalFinanceTraker/Models/RecurrenceFrequency.swift"
git commit -m "feat: add iCloud Drive entitlement and Codable conformance for backup"
```

---

### Task 2: Repository support for restore — `deleteAll*` methods and full-fidelity `RecurrenceRuleInput`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift` (protocol, ~L56-91; `RecurrenceRuleInput`, ~L216-239)
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift`
- Modify: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift`

**Interfaces:**
- Consumes: existing `ITransactionRepository`, `TransactionActor`, `RecurrenceRule.init(id:frequency:interval:startDate:endDate:lastMaterializedDate:amount:note:category:currencyCode:goalId:categoryModel:)` (already accepts `endDate`/`lastMaterializedDate`, just wasn't being passed them).
- Produces: `ITransactionRepository.deleteAllTransactions() async throws`, `ITransactionRepository.deleteAllRecurrenceRules() async throws`, and `RecurrenceRuleInput(id:frequency:interval:startDate:endDate:lastMaterializedDate:amount:note:category:currencyCode:goalId:categoryPersistentId:)` — used by `RestoreService` in Task 6 and `BackupMapper` in Task 3.

Today, restoring a recurrence rule via `addRecurrenceRule` would silently drop `endDate` (a closed rule comes back open-ended) and `lastMaterializedDate` (the materialization cursor resets, risking duplicate occurrences after restore). Fixing this now, before any backup exists in the wild, avoids a data-shape problem later.

- [ ] **Step 1: Write the failing tests**

Add to `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift` (inside the existing `TransactionActorRecurrenceTests` struct):

```swift
    @Test func addRecurrenceRulePreservesEndDateAndMaterializationCursor() async throws {
        let actor = makeActor()
        let input = RecurrenceRuleInput(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 6, 1),
            lastMaterializedDate: date(2026, 3, 1),
            amount: -1200,
            note: "Rent",
            category: "Housing",
            currencyCode: "EUR"
        )
        try await actor.addRecurrenceRule(input)

        let fetched = try await actor.fetchRecurrenceRule(id: input.id)
        #expect(fetched?.endDate == date(2026, 6, 1))
        #expect(fetched?.lastMaterializedDate == date(2026, 3, 1))
    }

    @Test func deleteAllTransactionsRemovesEverything() async throws {
        let actor = makeActor()
        try await actor.addBatch([
            TransactionInput(timestamp: date(2026, 1, 1), amount: -10, note: "A", category: "Food", currencyCode: "EUR"),
            TransactionInput(timestamp: date(2026, 1, 2), amount: -20, note: "B", category: "Food", currencyCode: "EUR")
        ])
        #expect(try await actor.fetchAll().count == 2)

        try await actor.deleteAllTransactions()

        #expect(try await actor.fetchAll().isEmpty)
    }

    @Test func deleteAllRecurrenceRulesRemovesEverything() async throws {
        let actor = makeActor()
        try await actor.addRecurrenceRule(ruleInput(startDate: date(2026, 1, 1)))
        try await actor.addRecurrenceRule(ruleInput(startDate: date(2026, 2, 1)))
        #expect(try await actor.fetchActiveRecurrenceRules().count == 2)

        try await actor.deleteAllRecurrenceRules()

        #expect(try await actor.fetchActiveRecurrenceRules().isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Use `ToolSearch` with `query: "select:mcp__xcode__RunSomeTests"`, then call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `TransactionActorRecurrenceTests`.
Expected: FAIL to compile — `deleteAllTransactions`/`deleteAllRecurrenceRules` don't exist yet, and `RecurrenceRuleInput` has no `endDate`/`lastMaterializedDate` parameters yet.

- [ ] **Step 3: Extend `RecurrenceRuleInput` and the protocol**

In `Models/TransactionRepository.swift`, change:
```swift
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
```

to:
```swift
struct RecurrenceRuleInput: Sendable {
    let id: UUID
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
    let categoryPersistentId: PersistentIdentifier?

    init(id: UUID = UUID(), frequency: RecurrenceFrequency, interval: Int, startDate: Date, endDate: Date? = nil, lastMaterializedDate: Date? = nil, amount: Decimal, note: String, category: String, currencyCode: String, goalId: UUID? = nil, categoryPersistentId: PersistentIdentifier? = nil) {
        self.id = id
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.lastMaterializedDate = lastMaterializedDate
        self.amount = amount
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.goalId = goalId
        self.categoryPersistentId = categoryPersistentId
    }
```

In the same file, add to the `ITransactionRepository` protocol (near the other recurrence-rule methods):
```swift
    func deleteAllTransactions() async throws
    func deleteAllRecurrenceRules() async throws
```

- [ ] **Step 4: Implement in `TransactionActor`**

Change `addRecurrenceRule` from:
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
```

to:
```swift
    func addRecurrenceRule(_ input: RecurrenceRuleInput) async throws {
        let rule = RecurrenceRule(
            id: input.id,
            frequency: input.frequency,
            interval: input.interval,
            startDate: input.startDate,
            endDate: input.endDate,
            lastMaterializedDate: input.lastMaterializedDate,
            amount: input.amount,
            note: input.note,
            category: input.category,
            currencyCode: input.currencyCode,
            goalId: input.goalId
        )
```

Add two new methods (near `delete(id:)`):
```swift
    func deleteAllTransactions() async throws {
        let all = try modelContext.fetch(FetchDescriptor<TransactionModel>())
        for model in all {
            modelContext.delete(model)
        }
        try modelContext.save()
    }

    func deleteAllRecurrenceRules() async throws {
        let all = try modelContext.fetch(FetchDescriptor<RecurrenceRule>())
        for model in all {
            modelContext.delete(model)
        }
        try modelContext.save()
    }
```

- [ ] **Step 5: Implement in `MockTransactionRepository`**

Add spy properties (near the other `*CalledCount` spies):
```swift
    var deleteAllTransactionsCalledCount = 0
    var deleteAllRecurrenceRulesCalledCount = 0
```

Add methods (near `delete(id:)`):
```swift
    func deleteAllTransactions() async throws {
        deleteAllTransactionsCalledCount += 1
        if shouldThrow { throw MockError.forced }
        stubbedTransactions.removeAll()
    }

    func deleteAllRecurrenceRules() async throws {
        deleteAllRecurrenceRulesCalledCount += 1
        if shouldThrow { throw MockError.forced }
        stubbedRecurrenceRules.removeAll()
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `TransactionActorRecurrenceTests`.
Expected: PASS, all three new tests plus the pre-existing ones in that file.

- [ ] **Step 7: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift" \
        "PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionActor.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/MockTransactionRepository.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/TransactionActorRecurrenceTests.swift"
git commit -m "feat: add deleteAll repository methods and full-fidelity recurrence rule restore"
```

---

### Task 3: Backup DTOs and snapshot mapping

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Models/BackupModels.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/BackupModelsTests.swift`

**Interfaces:**
- Consumes: `TransactionSnapshot`, `RecurrenceRuleSnapshot` (Task 2's extended `RecurrenceRuleInput`, via `BackupMapper.makeRecurrenceRuleInputs`), `TransactionInput`, `RecurrenceRuleInput`.
- Produces: `BackupTransaction`, `BackupRecurrenceRule`, `BackupPayload` (all `Codable, Sendable`), and `BackupMapper` with `makeTransactions(from:)`, `makeRecurrenceRules(from:)`, `makeTransactionInputs(from:)`, `makeRecurrenceRuleInputs(from:)` — used by `BackupService` (Task 4) and `RestoreService` (Task 6).

This is why these DTOs exist rather than encoding `TransactionSnapshot`/`RecurrenceRuleSnapshot` directly: neither snapshot type is `Codable` (both are only `Sendable, Hashable, Identifiable`), and their `id`/`categoryId`/`persistentId` fields are SwiftData `PersistentIdentifier`s with no stable meaning across a reinstalled store — a dedicated DTO keeps that internal identifier out of the on-disk JSON shape entirely.

- [ ] **Step 1: Write the failing test**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/BackupModelsTests.swift`:
```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct BackupModelsTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func transactionRoundTripsThroughBackupTransaction() {
        let ruleId = UUID()
        let snapshot = TransactionSnapshot.test(
            timestamp: date(2026, 1, 5),
            amount: -42.50,
            category: "Food",
            note: "Lunch",
            currencyCode: "EUR",
            recurrenceRuleId: ruleId
        )

        let backups = BackupMapper.makeTransactions(from: [snapshot])
        #expect(backups.count == 1)
        #expect(backups[0].amount == -42.50)
        #expect(backups[0].note == "Lunch")
        #expect(backups[0].recurrenceRuleId == ruleId)

        let inputs = BackupMapper.makeTransactionInputs(from: backups)
        #expect(inputs.count == 1)
        #expect(inputs[0].amount == -42.50)
        #expect(inputs[0].category == "Food")
        #expect(inputs[0].recurrenceRuleId == ruleId)
    }

    @Test func recurrenceRuleRoundTripsThroughBackupRecurrenceRule() {
        let snapshot = RecurrenceRuleSnapshot.test(
            frequency: .monthly,
            interval: 1,
            startDate: date(2026, 1, 1),
            amount: -1200,
            category: "Housing"
        )

        let backups = BackupMapper.makeRecurrenceRules(from: [snapshot])
        #expect(backups.count == 1)
        #expect(backups[0].frequency == .monthly)
        #expect(backups[0].amount == -1200)

        let inputs = BackupMapper.makeRecurrenceRuleInputs(from: backups)
        #expect(inputs.count == 1)
        #expect(inputs[0].id == snapshot.id)
        #expect(inputs[0].frequency == .monthly)
    }

    @Test func backupPayloadEncodesAndDecodesAsJSON() throws {
        let payload = BackupPayload(
            version: 1,
            createdAt: date(2026, 1, 1),
            transactions: [BackupTransaction(timestamp: date(2026, 1, 1), amount: -10, note: "A", category: "Food", currencyCode: "EUR", goalId: nil, recurrenceRuleId: nil)],
            recurrenceRules: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupPayload.self, from: data)

        #expect(decoded.transactions.count == 1)
        #expect(decoded.transactions[0].note == "A")
        #expect(decoded.version == 1)
    }
}
```

This assumes `TransactionSnapshot.test(...)` and `RecurrenceRuleSnapshot.test(...)` factory helpers already exist in `PersonalFinanceTrakerTests/Mocks/TransactionSnapshotFactory.swift` (per commit `5639b02`) — check that file first; if a parameter name here doesn't match (e.g. `recurrenceRuleId` isn't yet a factory parameter), add it to the factory with a `nil` default rather than changing this test.

- [ ] **Step 2: Run test to verify it fails**

Use `ToolSearch` with `query: "select:mcp__xcode__RunSomeTests"`, then call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `BackupModelsTests`.
Expected: FAIL to compile — `BackupTransaction`, `BackupRecurrenceRule`, `BackupPayload`, `BackupMapper` don't exist yet.

- [ ] **Step 3: Implement `BackupModels.swift`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Models/BackupModels.swift`:
```swift
import Foundation

struct BackupTransaction: Codable, Sendable {
    let timestamp: Date
    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let goalId: UUID?
    let recurrenceRuleId: UUID?
}

struct BackupRecurrenceRule: Codable, Sendable {
    let id: UUID
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
}

struct BackupPayload: Codable, Sendable {
    let version: Int
    let createdAt: Date
    let transactions: [BackupTransaction]
    let recurrenceRules: [BackupRecurrenceRule]
}

enum BackupMapper {
    static func makeTransactions(from snapshots: [TransactionSnapshot]) -> [BackupTransaction] {
        snapshots.map {
            BackupTransaction(
                timestamp: $0.timestamp,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId,
                recurrenceRuleId: $0.recurrenceRuleId
            )
        }
    }

    static func makeRecurrenceRules(from snapshots: [RecurrenceRuleSnapshot]) -> [BackupRecurrenceRule] {
        snapshots.map {
            BackupRecurrenceRule(
                id: $0.id,
                frequency: $0.frequency,
                interval: $0.interval,
                startDate: $0.startDate,
                endDate: $0.endDate,
                lastMaterializedDate: $0.lastMaterializedDate,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId
            )
        }
    }

    static func makeTransactionInputs(from backups: [BackupTransaction]) -> [TransactionInput] {
        backups.map {
            TransactionInput(
                timestamp: $0.timestamp,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId,
                recurrenceRuleId: $0.recurrenceRuleId
            )
        }
    }

    static func makeRecurrenceRuleInputs(from backups: [BackupRecurrenceRule]) -> [RecurrenceRuleInput] {
        backups.map {
            RecurrenceRuleInput(
                id: $0.id,
                frequency: $0.frequency,
                interval: $0.interval,
                startDate: $0.startDate,
                endDate: $0.endDate,
                lastMaterializedDate: $0.lastMaterializedDate,
                amount: $0.amount,
                note: $0.note,
                category: $0.category,
                currencyCode: $0.currencyCode,
                goalId: $0.goalId
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `BackupModelsTests`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/Models/BackupModels.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Models/BackupModelsTests.swift"
git commit -m "feat: add backup DTOs and snapshot mapping"
```

---

### Task 4: `BackupStorage` + `BackupService` — write, list, rotate, read

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupStorage.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupService.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/BackupServiceTests.swift`

**Interfaces:**
- Consumes: `TransactionSnapshot`, `RecurrenceRuleSnapshot`, `BackupPayload`, `BackupMapper` (Task 3).
- Produces: `BackupService.writeBackup(transactions:recurrenceRules:now:) throws -> URL`, `BackupService.listBackups() -> [URL]`, `BackupService.newestBackup() -> URL?`, `BackupService.readBackup(at:) throws -> BackupPayload`, `BackupService.BackupError` (`.iCloudUnavailable`, `.emptyStore`) — used by `BackupScheduler` (Task 5) and `RestoreService` (Task 6).

`BackupStorage` is a one-method protocol purely so tests can point `BackupService` at a temp directory instead of a real iCloud container — there's no other way to unit-test file I/O, rotation, and the empty-store guard without it.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/BackupServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct BackupServiceTests {
    private func makeTempStorage() -> (storage: TestBackupStorage, url: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (TestBackupStorage(url: dir), dir)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func writeBackupCreatesAJSONFileInTheContainer() throws {
        let (storage, dir) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2))

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.deletingLastPathComponent() == dir)
    }

    @Test func writeBackupThrowsWhenTransactionsAreEmpty() {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)

        #expect(throws: BackupService.BackupError.emptyStore) {
            try service.writeBackup(transactions: [], recurrenceRules: [], now: date(2026, 1, 1))
        }
    }

    @Test func writeBackupThrowsWhenICloudUnavailable() {
        let storage = TestBackupStorage(url: nil)
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        #expect(throws: BackupService.BackupError.iCloudUnavailable) {
            try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        }
    }

    @Test func newestBackupReturnsTheMostRecentlyWrittenFile() throws {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        let first = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))
        let second = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2, 9, 0))

        #expect(service.newestBackup() == second)
        #expect(service.newestBackup() != first)
    }

    @Test func writeBackupPrunesBeyondMaxBackupsKept() throws {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 2)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2, 9, 0))
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 3, 9, 0))

        #expect(service.listBackups().count == 2)
    }

    @Test func readBackupDecodesWhatWasWritten() throws {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food", note: "Lunch")]

        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        let payload = try service.readBackup(at: url)

        #expect(payload.transactions.count == 1)
        #expect(payload.transactions[0].note == "Lunch")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `BackupServiceTests`.
Expected: FAIL to compile — `BackupStorage`, `TestBackupStorage`, `BackupService` don't exist yet.

- [ ] **Step 3: Implement `BackupStorage.swift`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupStorage.swift`:
```swift
import Foundation

protocol BackupStorage: Sendable {
    /// Returns the directory backups should be written into, or nil if unavailable (e.g. no iCloud account).
    func containerURL() -> URL?
}

struct FileManagerBackupStorage: BackupStorage {
    func containerURL() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return base.appendingPathComponent("Documents", isDirectory: true)
    }
}
```

Also add the test double to the test target — create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/TestBackupStorage.swift`:
```swift
import Foundation
@testable import PersonalFinanceTraker

struct TestBackupStorage: BackupStorage {
    let url: URL?
    func containerURL() -> URL? { url }
}
```

- [ ] **Step 4: Implement `BackupService.swift`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupService.swift`:
```swift
import Foundation

final class BackupService {
    enum BackupError: Error, Equatable {
        case iCloudUnavailable
        case emptyStore
    }

    private let storage: BackupStorage
    private let maxBackupsKept: Int

    init(storage: BackupStorage = FileManagerBackupStorage(), maxBackupsKept: Int = 3) {
        self.storage = storage
        self.maxBackupsKept = maxBackupsKept
    }

    @discardableResult
    func writeBackup(transactions: [TransactionSnapshot], recurrenceRules: [RecurrenceRuleSnapshot], now: Date = Date()) throws -> URL {
        guard !transactions.isEmpty else { throw BackupError.emptyStore }
        guard let containerURL = storage.containerURL() else { throw BackupError.iCloudUnavailable }

        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let payload = BackupPayload(
            version: 1,
            createdAt: now,
            transactions: BackupMapper.makeTransactions(from: transactions),
            recurrenceRules: BackupMapper.makeRecurrenceRules(from: recurrenceRules)
        )
        let data = try Self.encoder.encode(payload)
        let fileURL = containerURL.appendingPathComponent(Self.filename(for: now))
        try data.write(to: fileURL, options: .atomic)

        pruneOldBackups(in: containerURL)
        return fileURL
    }

    func listBackups() -> [URL] {
        guard let containerURL = storage.containerURL() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)) ?? []
        // Filenames are ISO-8601-based, so lexicographic descending order is also newest-first.
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func newestBackup() -> URL? {
        listBackups().first
    }

    func readBackup(at url: URL) throws -> BackupPayload {
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(BackupPayload.self, from: data)
    }

    private func pruneOldBackups(in containerURL: URL) {
        let backups = listBackups()
        guard backups.count > maxBackupsKept else { return }
        for url in backups.dropFirst(maxBackupsKept) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func filename(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let safe = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "backup-\(safe).json"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
```

- [ ] **Step 5: Run tests to verify they pass**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `BackupServiceTests`.
Expected: PASS, all six tests.

- [ ] **Step 6: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupStorage.swift" \
        "PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupService.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Mocks/TestBackupStorage.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/BackupServiceTests.swift"
git commit -m "feat: add BackupService with atomic writes, rotation, and empty-store guard"
```

---

### Task 5: `AppSettings.lastBackupDate` + `BackupScheduler`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/AppSettings.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupScheduler.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/BackupSchedulerTests.swift`

**Interfaces:**
- Consumes: `ITransactionRepository`, `BackupService` (Task 4).
- Produces: `AppSettings.lastBackupDate: Date?`, `BackupSchedulingSettings` protocol, `BackupScheduler.runIfNeeded(repo:settings:backupService:now:) async` — used by the app entry point (Task 7) and by Profile's status line (Task 8).

The scheduler needs to both read and write "last backup date" in a unit test without touching real `UserDefaults`, so it depends on a tiny protocol instead of the concrete `AppSettings` class — the same reason `BackupStorage` exists in Task 4.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/BackupSchedulerTests.swift`:
```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

final class TestSchedulingSettings: BackupSchedulingSettings {
    var lastBackupDate: Date?
}

struct BackupSchedulerTests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeTempService() -> BackupService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return BackupService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)
    }

    @Test func runsBackupWhenNeverBackedUpBefore() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let settings = TestSchedulingSettings()
        let service = makeTempService()

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2))

        #expect(settings.lastBackupDate == date(2026, 1, 2))
        #expect(service.listBackups().count == 1)
    }

    @Test func skipsBackupWhenLastBackupIsFresh() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let settings = TestSchedulingSettings()
        settings.lastBackupDate = date(2026, 1, 2, 9)
        let service = makeTempService()

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2, 10))

        #expect(service.listBackups().isEmpty)
    }

    @Test func doesNotUpdateLastBackupDateWhenStoreIsEmpty() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = []
        let settings = TestSchedulingSettings()
        let service = makeTempService()

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2))

        #expect(settings.lastBackupDate == nil)
        #expect(service.listBackups().isEmpty)
    }

    @Test func doesNotUpdateLastBackupDateWhenICloudUnavailable() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let settings = TestSchedulingSettings()
        let service = BackupService(storage: TestBackupStorage(url: nil), maxBackupsKept: 3)

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2))

        #expect(settings.lastBackupDate == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `BackupSchedulerTests`.
Expected: FAIL to compile — `BackupSchedulingSettings`, `BackupScheduler` don't exist yet, and `AppSettings` doesn't conform.

- [ ] **Step 3: Add `lastBackupDate` to `AppSettings`**

In `Utilities/AppSettings.swift`, following the existing `payCycleStartDay` pattern, add:
```swift
    var lastBackupDate: Date? {
        didSet {
            UserDefaults.standard.set(lastBackupDate, forKey: "lastBackupDate")
        }
    }
```
and in `init()`, add:
```swift
        lastBackupDate = UserDefaults.standard.object(forKey: "lastBackupDate") as? Date
```

Then declare conformance to the new protocol (defined in Step 4) by changing the class declaration:
```swift
final class AppSettings: BackupSchedulingSettings {
```

- [ ] **Step 4: Implement `BackupScheduler.swift`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupScheduler.swift`:
```swift
import Foundation

protocol BackupSchedulingSettings: AnyObject {
    var lastBackupDate: Date? { get set }
}

enum BackupScheduler {
    static let staleInterval: TimeInterval = 24 * 60 * 60

    static func runIfNeeded(
        repo: ITransactionRepository,
        settings: BackupSchedulingSettings,
        backupService: BackupService,
        now: Date = Date()
    ) async {
        if let last = settings.lastBackupDate, now.timeIntervalSince(last) < staleInterval {
            return
        }
        guard let transactions = try? await repo.fetchAll() else { return }
        let rules = (try? await repo.fetchActiveRecurrenceRules()) ?? []

        do {
            try backupService.writeBackup(transactions: transactions, recurrenceRules: rules, now: now)
            settings.lastBackupDate = now
        } catch {
            // BackupError.emptyStore (fresh reinstall, nothing to back up yet) or .iCloudUnavailable —
            // skip silently and leave lastBackupDate untouched so the next foreground check retries.
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `BackupSchedulerTests`.
Expected: PASS, all four tests.

- [ ] **Step 6: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/Utilities/AppSettings.swift" \
        "PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupScheduler.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/BackupSchedulerTests.swift"
git commit -m "feat: add BackupScheduler with staleness and empty-store guards"
```

---

### Task 6: `RestoreService` — wipe-and-replace restore

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RestoreService.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/RestoreServiceTests.swift`

**Interfaces:**
- Consumes: `ITransactionRepository.deleteAllTransactions()`, `.deleteAllRecurrenceRules()`, `.addRecurrenceRule(_:)`, `.addBatch(_:)` (Task 2); `BackupService.newestBackup()`, `.readBackup(at:)` (Task 4); `BackupMapper.makeTransactionInputs(from:)`, `.makeRecurrenceRuleInputs(from:)` (Task 3).
- Produces: `RestoreService.restoreLatest(repo:backupService:) async throws`, `RestoreService.RestoreError.noBackupFound` — used by the Profile restore button (Task 8).

Restore order matters: recurrence rules are inserted before transactions so that any transaction referencing a `recurrenceRuleId` restores against a rule that already exists (defensive ordering; nothing in the current model actually enforces referential integrity, but there's no reason to rely on that).

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/RestoreServiceTests.swift`:
```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RestoreServiceTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeService(with payload: BackupPayload) -> BackupService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = TestBackupStorage(url: dir)
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        _ = try? service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")],
            recurrenceRules: [],
            now: date(2026, 1, 1)
        )
        return service
    }

    @Test func restoreLatestThrowsWhenNoBackupExists() async {
        let repo = MockTransactionRepository()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = BackupService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        await #expect(throws: RestoreService.RestoreError.noBackupFound) {
            try await RestoreService.restoreLatest(repo: repo, backupService: service)
        }
    }

    @Test func restoreLatestWipesThenRestoresFromNewestBackup() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = BackupService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        let ruleId = UUID()
        _ = try service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 5), amount: -42, category: "Food", note: "Lunch", recurrenceRuleId: ruleId)],
            recurrenceRules: [.test(id: ruleId, frequency: .monthly, interval: 1, startDate: date(2026, 1, 1), amount: -1200, category: "Housing")],
            now: date(2026, 1, 6)
        )

        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2020, 1, 1), amount: -1, category: "Stale")]

        try await RestoreService.restoreLatest(repo: repo, backupService: service)

        #expect(repo.deleteAllTransactionsCalledCount == 1)
        #expect(repo.deleteAllRecurrenceRulesCalledCount == 1)
        #expect(repo.addRecurrenceRuleCalls.count == 1)
        #expect(repo.addRecurrenceRuleCalls[0].id == ruleId)
        #expect(repo.addCalledCount == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `RestoreServiceTests`.
Expected: FAIL to compile — `RestoreService` doesn't exist yet.

- [ ] **Step 3: Implement `RestoreService.swift`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RestoreService.swift`:
```swift
import Foundation

enum RestoreService {
    enum RestoreError: Error, Equatable {
        case noBackupFound
    }

    static func restoreLatest(repo: ITransactionRepository, backupService: BackupService) async throws {
        guard let url = backupService.newestBackup() else { throw RestoreError.noBackupFound }
        let payload = try backupService.readBackup(at: url)

        try await repo.deleteAllTransactions()
        try await repo.deleteAllRecurrenceRules()

        for input in BackupMapper.makeRecurrenceRuleInputs(from: payload.recurrenceRules) {
            try await repo.addRecurrenceRule(input)
        }

        try await repo.addBatch(BackupMapper.makeTransactionInputs(from: payload.transactions))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Call `mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", ...)` targeting `RestoreServiceTests`.
Expected: PASS, both tests.

- [ ] **Step 5: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/Utilities/RestoreService.swift" \
        "PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/RestoreServiceTests.swift"
git commit -m "feat: add RestoreService for wipe-and-replace restore from latest backup"
```

---

### Task 7: Wire the foreground trigger into `AuthenticationWrapper`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/App/AuthenticationWrapper.swift`

**Interfaces:**
- Consumes: `BackupScheduler.runIfNeeded(repo:settings:backupService:now:)` (Task 5).

`AuthenticationWrapper` — not the `@main` App struct — is the right hook point: it already owns the single `AppSettings` instance (`@State private var appSettings = AppSettings()`, L18) and already has its own `@Environment(\.scenePhase)` handler (L11, L68-76) for lock/unlock. Reuse both rather than creating a second `AppSettings` instance elsewhere, which would just track the same `UserDefaults` key redundantly. This is SwiftUI lifecycle glue with no independent logic of its own (all the logic it calls is already tested in Task 5) — verify by running the app, not with a new unit test.

- [ ] **Step 1: Add the backup check to the existing scenePhase handler**

Current (`AuthenticationWrapper.swift` L9-21, L68-76):
```swift
struct AuthenticationWrapper: View {
    @StateObject private var authService = BiometricAuthService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isPINSetup: Bool = UserDefaults.standard.bool(forKey: "pin_setup_complete")
    @State private var showSplash = true
    // Owned here (not by MainTabView) since AuthenticationWrapper is never torn down
    // while the app is running — MainTabView is recreated on every lock/unlock cycle,
    // which would otherwise reset hideAmounts whenever the app is merely backgrounded.
    @State private var appSettings = AppSettings()

    private let pinService = PINService()
    let modelContainer: ModelContainer
```
```swift
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && isPINSetup {
                authService.lock()
            } else if newPhase == .active && isPINSetup && !authService.isUnlocked {
                if authService.isBiometricFeatureEnabled {
                    authService.authenticate { _ in }
                }
            }
        }
```

Change to — add `backupService` next to `pinService`:
```swift
    private let pinService = PINService()
    private let backupService = BackupService()
    let modelContainer: ModelContainer
```

and extend the existing `onChange(of: scenePhase)` (don't add a second one):
```swift
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && isPINSetup {
                authService.lock()
            } else if newPhase == .active && isPINSetup && !authService.isUnlocked {
                if authService.isBiometricFeatureEnabled {
                    authService.authenticate { _ in }
                }
            }
            if newPhase == .active {
                let repo = TransactionActor.make(modelContainer)
                let settings = appSettings
                let service = backupService
                Task {
                    await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service)
                }
            }
        }
```

- [ ] **Step 2: Build and manually verify**

Use `ToolSearch` with `query: "select:mcp__xcode__BuildProject"`, then call `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds. Then run the app in the simulator, background and foreground it, and confirm (via a breakpoint or temporary `print`) that `BackupScheduler.runIfNeeded` is invoked on foreground.

- [ ] **Step 3: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift"
git commit -m "feat: trigger backup check on app foreground"
```

---

### Task 8: Profile UI — backup status, manual backup, and restore

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift`

**Interfaces:**
- Consumes: `BackupService` (Task 4), `RestoreService.restoreLatest(repo:backupService:)` (Task 6), `AppSettings.lastBackupDate` (Task 5).

`ProfileView` already receives the app's single `AppSettings` instance via `.environment(appSettings)` (set up in `MainTabView.swift` L62, which received it from `AuthenticationWrapper`) — access it with `@Environment(AppSettings.self)`, the same mechanism the codebase already uses elsewhere, rather than constructing a new instance. Read backup status from `appSettings.lastBackupDate` directly rather than re-decoding the backup file — it's the same value `BackupScheduler` already maintains, so the manual "Backup Now" button below also updates it, keeping both paths consistent. No independent logic in this task — it wires already-tested services into SwiftUI views and a confirmation dialog. Verify by building and exercising the flow in the simulator (Profile > DATA > Backup Now / Restore), not with a new unit test.

- [ ] **Step 1: Add status line and Backup/Restore controls to the DATA section**

Current relevant section in `ProfileView.swift` (~L54-100):
```swift
                    Section {
                        Button {
                            showingFileImporter = true
                        } label: {
                            if transactionViewModel.isLoadingImportFile {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reading file…")
                                }
                            } else {
                                Label("Import CSV or Excel", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(transactionViewModel.isLoadingImportFile)

                        Menu {
                            ShareLink(
                                item: TransactionsExport(format: .csv, repo: transactionViewModel.repo),
                                preview: SharePreview("Transactions CSV")
                            ) {
                                Label("CSV", systemImage: "tablecells")
                            }

                            ShareLink(
                                item: TransactionsExport(format: .xlsx, repo: transactionViewModel.repo),
                                preview: SharePreview("Transactions Excel")
                            ) {
                                Label("Excel", systemImage: "tablecells.badge.ellipsis")
                            }
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete All Data", systemImage: "trash")
                                .foregroundStyle(.negative)
                        }
                    } header: {
                        Text("DATA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textDim)
                            .padding(.horizontal, 4)
                    }
                    .appFormSectionBackground()
```

Add, inside the same `Section` (after the "Export Data" `Menu`, before "Delete All Data"):
```swift
                        HStack {
                            Label(backupStatusText, systemImage: appSettings.lastBackupDate != nil ? "checkmark.icloud" : "exclamationmark.icloud")
                                .foregroundStyle(appSettings.lastBackupDate != nil ? .textDim : .negative)
                            Spacer()
                            Button("Backup Now") {
                                Task { await runManualBackup() }
                            }
                            .font(.caption)
                        }

                        Button {
                            showingRestoreConfirmation = true
                        } label: {
                            Label("Restore from Backup", systemImage: "arrow.clockwise.icloud")
                        }
                        .disabled(backupService.newestBackup() == nil)
```

Add supporting state and helpers to the view (near the other `@State` properties and the `showingDeleteConfirmation` confirmation dialog — `AppSettings` is added as an `@Environment` property, matching how the codebase already injects it elsewhere, e.g. for `hideAmounts`):
```swift
    @Environment(AppSettings.self) private var appSettings
    @State private var showingRestoreConfirmation = false
    @State private var isRestoring = false
    private let backupService = BackupService()

    private var backupStatusText: String {
        guard let lastBackupDate = appSettings.lastBackupDate else {
            return "Not backed up — enable iCloud Drive to protect against app deletion"
        }
        let formatter = RelativeDateTimeFormatter()
        return "Last backup: \(formatter.localizedString(for: lastBackupDate, relativeTo: .now))"
    }

    private func runManualBackup() async {
        let transactions = (try? await transactionViewModel.repo.fetchAll()) ?? []
        let rules = (try? await transactionViewModel.repo.fetchActiveRecurrenceRules()) ?? []
        guard (try? backupService.writeBackup(transactions: transactions, recurrenceRules: rules)) != nil else { return }
        appSettings.lastBackupDate = .now
    }
```

Add a confirmation dialog alongside the existing `showingDeleteConfirmation` one (same pattern — find where that one is declared in the view body and add this next to it):
```swift
        .confirmationDialog(
            "This replaces all current data with your last backup. This cannot be undone.",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                Task {
                    isRestoring = true
                    try? await RestoreService.restoreLatest(repo: transactionViewModel.repo, backupService: backupService)
                    isRestoring = false
                }
            }
            Button("Cancel", role: .cancel) {}
        }
```

`transactionViewModel.repo` (confirmed at `ProfileView.swift:218`, `let repo: any ITransactionRepository`) is already used a few lines above in `TransactionsExport(format:repo:)` — reuse it, matching the existing pattern exactly.

- [ ] **Step 2: Build and manually verify in the simulator**

Use `ToolSearch` with `query: "select:mcp__xcode__BuildProject"`, then call `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`.
Expected: build succeeds.

Then run the app: open Profile, confirm the status line shows "Not backed up…" on a fresh install, tap "Backup Now", confirm it flips to "Last backup: just now", then tap "Restore from Backup", confirm the dialog appears, confirm, and verify the data reloads correctly (a no-op restore onto the same data is fine as a smoke test — this validates wiring, not data correctness, which the Task 6 unit tests already cover).

- [ ] **Step 3: Commit**

```bash
git add "PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift"
git commit -m "feat: add backup status, manual backup, and restore to Profile"
```

---

## Self-Review Notes

- **Spec coverage:** iCloud Drive storage (Task 4/7), plaintext JSON no encryption (Task 3/4, per spec's rejected-alternatives), 24h foreground trigger (Task 5/7), empty-store guard (Task 4's `BackupError.emptyStore`), backup rotation (Task 4's `maxBackupsKept`), atomic writes (Task 4's `.atomic`), wipe-and-replace restore with confirmation (Task 6/8), newest-backup-wins with no picker UI (Task 4's `newestBackup()`), status indicator collapsed to one bit (Task 8), dedicated backup DTOs excluding `PersistentIdentifier` (Task 3), full-fidelity recurrence rule restore including `endDate`/`lastMaterializedDate` (Task 2) — all covered.
- **Type consistency checked:** `RecurrenceRuleInput`'s new fields (Task 2) match `BackupMapper.makeRecurrenceRuleInputs` (Task 3) and `RestoreServiceTests` usage (Task 6). `BackupService`'s constructor signature (Task 4) matches every call site in Tasks 5-8. `BackupSchedulingSettings` (Task 5) is satisfied by `AppSettings` and by the test double consistently. `TransactionSnapshot.test(...)`/`RecurrenceRuleSnapshot.test(...)` factory signatures (`TransactionSnapshotFactory.swift`) were read directly and match every test in Tasks 3, 4, and 6 verbatim — no guessed parameter names remain. `AuthenticationWrapper.swift` and `MainTabView.swift` were read directly to confirm the real `AppSettings` ownership and environment-injection points used in Tasks 7 and 8, replacing what would otherwise have been an assumption.
