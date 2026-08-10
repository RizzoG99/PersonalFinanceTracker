# Multi-select + bulk edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a selection mode to the Activity list that bulk-deletes, recategorizes, re-amounts, or re-describes several transactions at once, each reversible via the existing undo banner.

**Architecture:** All logic lives in `TransactionListViewModel`. The existing delete-with-5s-undo machinery (`pendingDeletion`/`deleteProgress`/`pendingDeletionTask`/`commitPendingDeletion`/`undoDelete`) is generalized into a pending-mutation-with-undo path: delete stays "arm + commit-on-timeout"; edits are "apply immediately + arm a revert closure." Bulk mutations loop the existing `repo.update`/`repo.delete` — no new repo methods. The UI adds selection chrome to `ActivityView` and a bottom action bar with per-action input sheets.

**Tech Stack:** SwiftUI, SwiftData (`PersistentIdentifier`), `@Observable @MainActor` view model, Swift Testing (`@Test`/`#expect`), EUR hardcoded.

## Global Constraints

- **Build/test via Xcode MCP only** (`mcp__xcode__BuildProject` / `RunAllTests`, `tabIdentifier` verified via `XcodeListWindows` — it changes per Xcode launch). `xcodebuild` is BANNED.
- **Swift Testing**, not XCTest: `@Test`, `#expect`, `#require`, `@testable import PersonalFinanceTraker`. Use `MockTransactionRepository` and/or `SampleData.populateModelContext()`.
- **Expenses are negative `Decimal`**, income positive. Bulk amount edits **preserve each row's existing sign** — never flip expense↔income.
- **No new repository methods.** Bulk = loop `repo.update(id:with:)` / `repo.delete(id:)`. Mark the loop `// ponytail: loop update; add updateBatch only if it measurably lags`.
- **Localize** all user-facing copy with `String(localized:)`; add new keys to `Localizable.xcstrings` (en + it) via targeted splice (do NOT re-dump the whole file — it explodes the diff). Plurals go through the catalog's plural variation, matching the existing `"\(count) transaction deleted"` key.
- **Undo path parity:** the generalized path must not change single-row delete or its recurrence-prompt behavior. Existing delete tests must stay green.
- Directory is `PersonalFinanceTraker` (missing 'c').

---

## File Structure

- **Modify** `Features/TransactionListView/TransactionListViewModel.swift` — selection state (Task 1), generalized undo path (Task 2), bulk mutation methods (Task 3).
- **Modify** `Features/TransactionListView/ActivityView.swift` — selection chrome, long-press entry, action bar, input sheets (Task 4).
- **Modify** `Features/MainTabView/MainTabView.swift` — banner message wiring (Task 4).
- **Modify** `PersonalFinanceTraker/Localizable.xcstrings` — new keys (Task 4).
- **Modify** `PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift` — unit tests (Tasks 1–3).

Reference shapes (do not restate in code — import them):
- `TransactionSnapshot` (`Models/Snapshots.swift:10`): `id: PersistentIdentifier`, `timestamp`, `amount: Decimal`, `note`, `category: String`, `currencyCode`, `goalId: UUID?`, `recurrenceRuleId: UUID?`, `categoryId: PersistentIdentifier?`.
- `TransactionInput` (`Snapshots.swift:145`): `init(timestamp:amount:note:category:currencyCode:goalId:categoryPersistentId:recurrenceRuleId:)`.
- `CategorySnapshot` (`Snapshots.swift:38`): `name: String`, `persistentId: PersistentIdentifier`.
- `repo.update(id:with:)` (`TransactionActor.swift:72`) writes timestamp/amount/note/category/currency/goal/categoryModel — **never** recurrence linkage.

---

### Task 1: Selection state

**Files:**
- Modify: `Features/TransactionListView/TransactionListViewModel.swift`
- Test: `PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift`

**Interfaces:**
- Produces: `isSelecting: Bool`, `selectedIDs: Set<PersistentIdentifier>`, `toggleSelection(_:)`, `selectAllVisible()`, `deselectAll()`, `exitSelection()`, `selectedSnapshots: [TransactionSnapshot]`, `allVisibleSelected: Bool`.
- Consumes: existing `filteredItems`, `transactions`, and the `filteredItems.didSet` block.

- [ ] **Step 1: Write the failing tests**

Add to `TransactionListViewModelTests.swift` (use the existing test setup pattern — a `MockTransactionRepository` seeded with a few snapshots; mirror an existing test's construction):

```swift
@Test @MainActor func toggleSelectionAddsAndRemoves() async {
    let vm = await makeLoadedVM()               // helper: builds VM, seeds repo, awaits load
    let id = vm.filteredItems[0].id
    vm.toggleSelection(id)
    #expect(vm.selectedIDs.contains(id))
    vm.toggleSelection(id)
    #expect(!vm.selectedIDs.contains(id))
}

@Test @MainActor func selectAllVisibleSelectsOnlyFiltered() async {
    let vm = await makeLoadedVM()
    vm.searchText = "coffee"                     // narrow to a subset
    try? await vm.searchDebounceTask?.value
    vm.selectAllVisible()
    #expect(vm.selectedIDs == Set(vm.filteredItems.map(\.id)))
    #expect(vm.selectedIDs.count < vm.transactions.count)   // hidden rows excluded
}

@Test @MainActor func filteringOutSelectedRowDropsIt() async {
    let vm = await makeLoadedVM()
    let id = vm.filteredItems.first { $0.note.localizedCaseInsensitiveContains("coffee") == false }!.id
    vm.toggleSelection(id)
    vm.searchText = "coffee"
    try? await vm.searchDebounceTask?.value
    #expect(!vm.selectedIDs.contains(id))        // intersected out
}

@Test @MainActor func exitSelectionClearsState() async {
    let vm = await makeLoadedVM()
    vm.isSelecting = true
    vm.toggleSelection(vm.filteredItems[0].id)
    vm.exitSelection()
    #expect(!vm.isSelecting)
    #expect(vm.selectedIDs.isEmpty)
}
```

If a `makeLoadedVM()` helper does not already exist in this test file, add one that mirrors the existing tests' VM construction (seed the mock repo with at least one row whose note contains "coffee" and several that do not), and `await` the load task.

- [ ] **Step 2: Run tests to verify they fail**

Xcode MCP `RunSomeTests` for the four new tests. Expected: FAIL (members don't exist).

- [ ] **Step 3: Implement selection state**

In `TransactionListViewModel`, add stored state near the other `var`s:

```swift
// MARK: - Multi-select
var isSelecting = false
var selectedIDs: Set<PersistentIdentifier> = []

var selectedSnapshots: [TransactionSnapshot] {
    transactions.filter { selectedIDs.contains($0.id) }
}

/// True when every currently visible row is selected (drives the Select All / Deselect All label).
var allVisibleSelected: Bool {
    !filteredItems.isEmpty && filteredItems.allSatisfy { selectedIDs.contains($0.id) }
}

func toggleSelection(_ id: PersistentIdentifier) {
    if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
}

func selectAllVisible() {
    selectedIDs = Set(filteredItems.map(\.id))
}

func deselectAll() {
    selectedIDs.removeAll()
}

func exitSelection() {
    isSelecting = false
    selectedIDs.removeAll()
}
```

In the existing `filteredItems` `didSet` (currently calls `updateGroupedItems()` + `recomputeDerivedFilterState()`), append an intersection so hidden rows drop from the selection:

```swift
var filteredItems: [TransactionSnapshot] = [] {
    didSet {
        updateGroupedItems()
        recomputeDerivedFilterState()
        intersectSelectionWithVisible()
    }
}

private func intersectSelectionWithVisible() {
    guard !selectedIDs.isEmpty else { return }
    let visible = Set(filteredItems.map(\.id))
    selectedIDs.formIntersection(visible)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Xcode MCP `RunSomeTests` for the four tests. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift
git commit -m "feat: add multi-select state to TransactionListViewModel"
```

---

### Task 2: Generalize the undo path

**Files:**
- Modify: `Features/TransactionListView/TransactionListViewModel.swift`
- Test: `PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift`

**Interfaces:**
- Produces: `pendingUndoMessage: String`, `armUndo(message:revert:)`, `commitPending()` (branches on mutation kind), `undoPending()`. `undoDelete()` and `commitPendingDeletion()` remain (delete case).
- Consumes: existing `pendingDeletion`, `pendingDeletionTask`, `deleteProgress`, `showUndoBanner`, `scheduleDeletion`.

**Design:** `pendingRevert != nil` marks an *edit* (write already persisted; timeout is a no-op; undo runs the revert). `pendingRevert == nil` marks a *delete* (timeout runs the existing `repo.delete` loop; undo just `reload()`s since nothing was committed). The timeout path **must** branch — falling into the delete loop for an edit would delete nothing or crash (Gap 2).

- [ ] **Step 1: Write the failing tests**

```swift
@Test @MainActor func armUndoForEditDoesNotDeleteOnTimeout() async {
    let vm = await makeLoadedVM()
    let before = vm.transactions.count
    var reverted = false
    await vm.armUndo(message: "2 transactions updated") { reverted = true }
    #expect(vm.showUndoBanner)
    #expect(vm.pendingDeletion.isEmpty)          // edit path never populates pendingDeletion
    await vm.commitPending()                       // simulate timeout firing
    #expect(vm.transactions.count == before)      // Gap 2: nothing deleted
    #expect(!reverted)                             // commit is a no-op; revert only runs on undo
    #expect(!vm.showUndoBanner)
}

@Test @MainActor func undoForEditRunsRevert() async {
    let vm = await makeLoadedVM()
    var reverted = false
    await vm.armUndo(message: "x") { reverted = true }
    vm.undoPending()
    await vm.bulkEditTask?.value   // undo's revert Task, exposed via the shared handle
    #expect(reverted)
    #expect(!vm.showUndoBanner)
}

@Test @MainActor func singleDeleteStillCommits() async {   // regression
    let vm = await makeLoadedVM()
    let item = vm.filteredItems.first { $0.recurrenceRuleId == nil }!
    let before = vm.transactions.count
    vm.delete(item)
    await vm.commitPending()
    #expect(vm.transactions.count == before - 1)
    #expect(vm.pendingDeletion.isEmpty)
}

// Cross-kind flush: arming an edit while a delete is pending must FINALIZE the delete
// (commit it), not abandon it. Without the flush the removed rows would reappear on
// the next reload — the blocking leak this guards against.
@Test @MainActor func armingEditFlushesPendingDelete() async {
    let vm = await makeLoadedVM()
    let item = vm.filteredItems.first { $0.recurrenceRuleId == nil }!
    vm.delete(item)                       // arm a delete: row removed, pendingDeletion=[item]
    #expect(vm.pendingDeletion.count == 1)
    await vm.armUndo(message: "edited") { }   // arming an edit flushes the pending delete
    let after = try! await vm.repo.fetchAll()
    #expect(!after.contains { $0.id == item.id })   // delete was committed, not leaked
    #expect(vm.pendingDeletion.isEmpty)
    #expect(vm.showUndoBanner)                        // edit's banner now showing
}
```

- [ ] **Step 2: Run tests to verify they fail**

`RunSomeTests`. Expected: FAIL (`armUndo`/`commitPending`/`undoPending` undefined).

- [ ] **Step 3: Implement the generalized path**

Add state near `showUndoBanner`:

```swift
var pendingUndoMessage: String = ""
/// Non-nil marks the pending mutation as an *edit* (already persisted): timeout is a no-op,
/// undo runs this closure. Nil marks a *delete*: timeout runs the repo.delete loop.
@ObservationIgnored private var pendingRevert: (() async -> Void)?
/// Handle to the in-flight bulk-edit apply / undo-revert Task so tests await instead of sleeping.
@ObservationIgnored private(set) var bulkEditTask: Task<Void, Never>?
```

Add the shared arm/commit/undo API:

```swift
/// Arm the 5s undo banner for an already-applied edit. `revert` restores prior state on undo.
/// `async` because it must FINALIZE any in-flight mutation before arming a new one —
/// otherwise a pending delete (rows removed from `transactions`, not yet committed) would be
/// abandoned when `pendingRevert` is set and `commitPending()` takes the edit branch.
func armUndo(message: String, revert: @escaping () async -> Void) async {
    if showUndoBanner { await commitPending() }   // commit a prior delete / clear a prior edit
    pendingDeletionTask?.cancel()
    pendingUndoMessage = message
    pendingRevert = revert
    deleteProgress = 0.0
    showUndoBanner = true
    pendingDeletionTask = startUndoTimer()
}

/// Shared 5s progress timer, extracted from scheduleDeletion.
private func startUndoTimer() -> Task<Void, Never> {
    Task {
        let start = Date.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            deleteProgress = min(Date.now.timeIntervalSince(start) / 5.0, 1.0)
            if deleteProgress >= 1.0 { break }
        }
        guard !Task.isCancelled else { return }
        await commitPending()
    }
}

/// Timeout finalizer. Branches on mutation kind (Gap 2): an edit's commit must NOT
/// run the delete loop.
func commitPending() async {
    if pendingRevert != nil {
        // Edit: write already persisted; just clear the banner.
        pendingRevert = nil
        pendingUndoMessage = ""
        showUndoBanner = false
        deleteProgress = 0.0
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
    } else {
        await commitPendingDeletion()   // existing delete loop, unchanged
    }
}

/// Undo for either mutation kind.
func undoPending() {
    pendingDeletionTask?.cancel()
    pendingDeletionTask = nil
    if let revert = pendingRevert {
        pendingRevert = nil
        pendingUndoMessage = ""
        showUndoBanner = false
        deleteProgress = 0.0
        bulkEditTask = Task { await revert(); onDataChanged?(); reload() }   // exposed so tests await, not sleep
    } else {
        undoDelete()   // existing delete-undo (reload restores uncommitted rows)
    }
}
```

Refactor `scheduleDeletion` to reuse the timer and set the message (keep its in-memory removal + `pendingDeletion` population exactly as-is):

```swift
private func scheduleDeletion(_ items: [TransactionSnapshot]) {
    // NOTE: deliberately does NOT flush a prior pending mutation.
    //  - delete→delete: appending to pendingDeletion is intentional batching (swipe two
    //    rows quickly → one combined banner); flushing would split it into two banners.
    //  - edit→delete: setting `pendingRevert = nil` below makes commitPending() take the
    //    delete branch, and the prior edit was already persisted — no leak, nothing to flush.
    // Only delete→edit leaks, and that is finalized in armUndo (the edit arm), not here.
    pendingDeletionTask?.cancel()
    pendingDeletion.append(contentsOf: items)
    let ids = Set(items.map(\.id))
    transactions.removeAll { ids.contains($0.id) }
    Task { await doFilterItemBySearchText() }
    pendingRevert = nil                                  // delete case
    pendingUndoMessage = String(localized: "\(pendingDeletion.count) transaction deleted")
    deleteProgress = 0.0
    showUndoBanner = true
    pendingDeletionTask = startUndoTimer()
}
```

Leave `commitPendingDeletion()` and `undoDelete()` bodies unchanged.

- [ ] **Step 4: Run tests to verify they pass**

`RunSomeTests` for the three new tests **plus** any pre-existing delete/undo tests in the file. Expected: PASS (regression tests included).

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift
git commit -m "refactor: generalize undo banner path for edits and deletes"
```

---

### Task 3: Bulk mutation methods

**Files:**
- Modify: `Features/TransactionListView/TransactionListViewModel.swift`
- Test: `PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift`

**Interfaces:**
- Produces: `bulkDelete()`, `bulkSetCategory(_:)`, `bulkSetAmount(_:)`, `bulkSetNote(_:)`.
- Consumes: Task 1 selection state, Task 2 `armUndo`, existing `scheduleDeletion`, `repo.update`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test @MainActor func bulkDeleteRemovesSelected() async {
    let vm = await makeLoadedVM()
    let targets = Array(vm.filteredItems.prefix(2))
    targets.forEach { vm.toggleSelection($0.id) }
    let before = vm.transactions.count
    vm.bulkDelete()
    #expect(!vm.isSelecting)
    await vm.commitPending()
    #expect(vm.transactions.count == before - 2)
}

@Test @MainActor func bulkSetCategoryRewritesOnlySelected() async {
    let vm = await makeLoadedVM()
    let cat = try! await vm.repo.fetchCategories().first!
    let target = vm.filteredItems[0]
    let other = vm.filteredItems[1]
    let otherCatBefore = other.category
    vm.toggleSelection(target.id)
    vm.bulkSetCategory(cat)
    await vm.bulkEditTask?.value
    let after = try! await vm.repo.fetchAll()
    #expect(after.first { $0.id == target.id }!.category == cat.name)
    #expect(after.first { $0.id == other.id }!.category == otherCatBefore)   // untouched
    #expect(vm.showUndoBanner)
}

@Test @MainActor func bulkSetAmountPreservesSign() async {
    let vm = await makeLoadedVM()
    let expense = vm.filteredItems.first { $0.amount < 0 }!
    let income = vm.filteredItems.first { $0.amount > 0 }!
    vm.toggleSelection(expense.id); vm.toggleSelection(income.id)
    vm.bulkSetAmount(25)
    await vm.bulkEditTask?.value
    let after = try! await vm.repo.fetchAll()
    #expect(after.first { $0.id == expense.id }!.amount == -25)   // stays negative
    #expect(after.first { $0.id == income.id }!.amount == 25)     // stays positive
}

@Test @MainActor func bulkSetNoteOverwritesSelected() async {
    let vm = await makeLoadedVM()
    let target = vm.filteredItems[0]
    vm.toggleSelection(target.id)
    vm.bulkSetNote("reconciled")
    await vm.bulkEditTask?.value
    let after = try! await vm.repo.fetchAll()
    #expect(after.first { $0.id == target.id }!.note == "reconciled")
}

@Test @MainActor func bulkEditUndoRestoresPriorValues() async {
    let vm = await makeLoadedVM()
    let target = vm.filteredItems[0]
    let priorNote = target.note
    vm.toggleSelection(target.id)
    vm.bulkSetNote("changed")
    await vm.bulkEditTask?.value
    vm.undoPending()
    await vm.bulkEditTask?.value
    let after = try! await vm.repo.fetchAll()
    #expect(after.first { $0.id == target.id }!.note == priorNote)
}

@Test @MainActor func bulkDeleteRecurringDoesNotCloseRule() async {
    let vm = await makeLoadedVM()
    guard let recurring = vm.filteredItems.first(where: { $0.recurrenceRuleId != nil }) else { return }
    let ruleId = recurring.recurrenceRuleId!
    vm.toggleSelection(recurring.id)
    vm.bulkDelete()
    await vm.commitPending()
    // The rule must still exist (bulk delete is this-only).
    let rules = try! await vm.repo.fetchRecurrenceRules()
    #expect(rules.contains { $0.id == ruleId })
}

@Test @MainActor func bulkOpsNoopOnEmptySelection() async {
    let vm = await makeLoadedVM()
    let before = vm.transactions.count
    vm.bulkDelete()
    vm.bulkSetNote("x")
    #expect(vm.transactions.count == before)
    #expect(!vm.showUndoBanner)
}
```

(If the mock repo lacks `fetchRecurrenceRules`, use whichever existing accessor the codebase provides to assert the rule survives; the recurring test may early-return when the seed has no recurring row — seed one if practical.)

- [ ] **Step 2: Run tests to verify they fail**

`RunSomeTests`. Expected: FAIL (`bulk*` undefined).

- [ ] **Step 3: Implement bulk methods**

```swift
// MARK: - Bulk actions

/// Reconstruct a lossless input from a snapshot, optionally overriding amount or note.
/// Always preserves category linkage; category changes build their input directly (below).
private func input(from s: TransactionSnapshot,
                   amount: Decimal? = nil,
                   note: String? = nil) -> TransactionInput {
    TransactionInput(
        timestamp: s.timestamp,
        amount: amount ?? s.amount,
        note: note ?? s.note,
        category: s.category,
        currencyCode: s.currencyCode,
        goalId: s.goalId,
        categoryPersistentId: s.categoryId,
        recurrenceRuleId: s.recurrenceRuleId
    )
}

func bulkDelete() {
    let targets = selectedSnapshots
    guard !targets.isEmpty else { return }
    exitSelection()
    scheduleDeletion(targets)   // plain delete, no recurrence prompt (matches existing multi-delete path)
}

func bulkSetCategory(_ category: CategorySnapshot) {
    applyBulkEdit(message: { String(localized: "\($0) transactions updated") }) { s in
        // Build directly — this is the one edit that changes category name + persistentId together.
        TransactionInput(
            timestamp: s.timestamp,
            amount: s.amount,
            note: s.note,
            category: category.name,
            currencyCode: s.currencyCode,
            goalId: s.goalId,
            categoryPersistentId: category.persistentId,
            recurrenceRuleId: s.recurrenceRuleId
        )
    }
}

func bulkSetAmount(_ magnitude: Decimal) {
    applyBulkEdit(message: { String(localized: "\($0) transactions updated") }) { s in
        // Preserve sign: expenses stay negative, income positive.
        let signed = s.amount < 0 ? -abs(magnitude) : abs(magnitude)
        return self.input(from: s, amount: signed)
    }
}

func bulkSetNote(_ note: String) {
    applyBulkEdit(message: { String(localized: "\($0) transactions updated") }) { s in
        self.input(from: s, note: note)
    }
}

/// Shared edit driver: capture prior inputs, apply new inputs, arm the undo banner with a revert.
/// Order matters: write edits → `await armUndo` (which finalizes any prior pending mutation) →
/// reload. Reloading only after the flush avoids a transient reappear-then-vanish flicker of a
/// prior delete's rows.
private func applyBulkEdit(message: (Int) -> String,
                           newInput: @escaping (TransactionSnapshot) -> TransactionInput) {
    let targets = selectedSnapshots
    guard !targets.isEmpty else { return }
    let count = targets.count
    let prior: [(PersistentIdentifier, TransactionInput)] = targets.map { ($0.id, input(from: $0)) }
    let text = message(count)
    exitSelection()
    bulkEditTask = Task {
        // ponytail: loop update; add updateBatch only if it measurably lags
        for t in targets {
            try? await repo.update(id: t.id, with: newInput(t))
        }
        await armUndo(message: text) {
            for (id, input) in prior { try? await self.repo.update(id: id, with: input) }
        }
        onDataChanged?()
        reload()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

`RunSomeTests` for the seven new tests. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/TransactionListView/TransactionListViewModelTests.swift
git commit -m "feat: add bulk delete/category/amount/note actions"
```

---

### Task 4: Selection UI in the Activity list

**Files:**
- Modify: `Features/TransactionListView/ActivityView.swift`
- Modify: `Features/MainTabView/MainTabView.swift`
- Modify: `PersonalFinanceTraker/Localizable.xcstrings`

**Interfaces:**
- Consumes: all Task 1–3 view-model API. No new VM members.

This task is view-layer; it is verified by **build + manual run**, not unit tests (per project convention for pure SwiftUI wiring).

- [ ] **Step 1: Long-press entry + tap branching + selection circle**

In `ActivityView.swift`, the row is currently:

```swift
Button {
    viewModel.transactionToEdit = item
} label: {
    TransactionItemView(item: item)
}
.buttonStyle(.plain)
```

Replace with selection-aware behavior. Show a leading circle while selecting; tap toggles selection instead of opening the edit sheet; long-press enters selection with the row selected:

```swift
Button {
    if viewModel.isSelecting {
        viewModel.toggleSelection(item.id)
    } else {
        viewModel.transactionToEdit = item
    }
} label: {
    HStack(spacing: 12) {
        if viewModel.isSelecting {
            Image(systemName: viewModel.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(viewModel.selectedIDs.contains(item.id) ? Color.accentIndigo : Color.textSecondary)
                .accessibilityHidden(true)
        }
        TransactionItemView(item: item)
    }
}
.buttonStyle(.plain)
.onLongPressGesture {
    if !viewModel.isSelecting {
        viewModel.isSelecting = true
        viewModel.toggleSelection(item.id)
    }
}
```

Gate swipe-to-delete off while selecting so it doesn't compete — wrap the existing `.swipeActions(...)` content in `if !viewModel.isSelecting { ... }`, or add `.deleteDisabled(viewModel.isSelecting)` equivalent by making the swipe buttons conditional. (Use `Color.accentIndigo` / `Color.textSecondary` — confirm the exact token names against `DesignTokens.swift`; substitute the nearest existing tokens if these differ.)

- [ ] **Step 2: Selection toolbar**

Add a `.toolbar` to the Activity list (or extend the existing one) that appears while `viewModel.isSelecting`:

```swift
.toolbar {
    if viewModel.isSelecting {
        ToolbarItem(placement: .topBarLeading) {
            Button(String(localized: "Cancel")) { viewModel.exitSelection() }
        }
        ToolbarItem(placement: .principal) {
            Text("\(viewModel.selectedIDs.count) selected").font(.headline)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(viewModel.allVisibleSelected ? String(localized: "Deselect All") : String(localized: "Select All")) {
                if viewModel.allVisibleSelected { viewModel.deselectAll() } else { viewModel.selectAllVisible() }
            }
        }
    }
}
```

- [ ] **Step 3: Bottom action bar + input sheets**

Add a bottom bar overlay shown while `viewModel.isSelecting`, disabled when `selectedIDs.isEmpty`. Four buttons; three open input sheets showing the count, the fourth deletes:

```swift
@State private var showCategorySheet = false
@State private var showAmountSheet = false
@State private var showNoteSheet = false
```

Overlay (pin to bottom, above the tab bar), each label with an SF Symbol + `String(localized:)`:

```swift
.safeAreaInset(edge: .bottom) {
    if viewModel.isSelecting {
        HStack {
            bulkButton("Delete", "trash", role: .destructive) { viewModel.bulkDelete() }
            bulkButton("Category", "tag") { showCategorySheet = true }
            bulkButton("Amount", "eurosign.circle") { showAmountSheet = true }
            bulkButton("Description", "text.alignleft") { showNoteSheet = true }
        }
        .disabled(viewModel.selectedIDs.isEmpty)
        .padding()
        .background(.ultraThinMaterial)
    }
}
```

- **Category sheet:** reuse the app's existing category presentation (e.g. the compact `CategoryPickerSheet`/`CategoryChipsGrid` from the Add flow, or a simple `List` of `viewModel`-provided categories — fetch via `repo.fetchCategories()` into local `@State`). Title `Text("Set category for \(viewModel.selectedIDs.count) transactions")`. On pick → `viewModel.bulkSetCategory(cat)` and dismiss.
- **Amount sheet:** a `CurrencyAmountField`-based input. Title `Set \(count) transactions to …`. On confirm → `viewModel.bulkSetAmount(value)`.
- **Description sheet:** a `TextField`. Title `Set description for \(count) transactions`. On confirm → `viewModel.bulkSetNote(text)`.

Each sheet's title MUST include the count (the overwrite must be obvious at confirm).

- [ ] **Step 4: Banner message wiring**

In `MainTabView.swift`, the undo banner currently hardcodes the deleted-count copy. Point it at the generalized message and undo handler:
- Change the banner's message source to `viewModel.pendingUndoMessage` (so edits read "N transactions updated").
- Change its Undo action to call `viewModel.undoPending()` instead of `undoDelete()`.

(`UndoDeleteBanner` takes a `message: String` — pass `viewModel.pendingUndoMessage`; keep the progress ring bound to `viewModel.deleteProgress`.)

- [ ] **Step 5: Localize**

Add to `Localizable.xcstrings` (en + it) via targeted splice — do NOT re-dump the whole file. New keys:

| Key | en | it |
|-----|----|----|
| `%lld selected` | `%lld selected` | `%lld selezionati` |
| `Select All` | `Select All` | `Seleziona tutto` |
| `Deselect All` | `Deselect All` | `Deseleziona tutto` |
| `Category` | `Category` | `Categoria` |
| `Amount` | `Amount` | `Importo` |
| `Description` | `Description` | `Descrizione` |
| `%lld transactions updated` | `%lld transactions updated` | `%lld transazioni aggiornate` |
| `Set category for %lld transactions` | … | `Imposta categoria per %lld transazioni` |
| `Set %lld transactions to` | … | `Imposta %lld transazioni a` |
| `Set description for %lld transactions` | … | `Imposta descrizione per %lld transazioni` |

(Use the plural variation for the count keys, matching the existing `"%lld transaction deleted"` entry. `Delete`/`Cancel` almost certainly already exist — reuse, don't duplicate.)

- [ ] **Step 6: Build + manual verify**

Xcode MCP `BuildProject`. Then run on simulator and verify:
- Long-press a row → selection mode, that row checked, toolbar shows "1 selected".
- Tapping rows toggles; Select All / Deselect All scoped to visible rows (search first to confirm).
- Action bar disabled at 0 selected; enabled otherwise.
- Each action: input sheet shows the count; applying blanks selection, shows the undo banner with the right copy; Undo restores prior values.
- Delete shows "N transactions deleted"; recurring row deleted this-only leaves its series intact.
- Swipe-to-delete suppressed while selecting; normal (non-selecting) tap still opens the edit sheet.

- [ ] **Step 7: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/ActivityView.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift PersonalFinanceTraker/PersonalFinanceTraker/Localizable.xcstrings
git commit -m "feat: multi-select UI and bulk action bar in Activity list"
```

---

## Self-Review Notes

- **Spec coverage:** entry (T4 long-press), chrome (T4 toolbar + action bar), all four actions (T3 + T4 sheets), undo generalization incl. Gap 2 branch (T2), sign preservation (T3), recurring-under-delete + under-edit (T3 tests + `update` never touches linkage), Select-All-visible-only (T1), count-at-confirm (T4 sheet titles), no new repo methods (T3 loop) — all mapped.
- **Type consistency:** `input(from:)` uses the exact `TransactionInput` initializer; category string = `CategorySnapshot.name`, id = `.persistentId`, matching `buildInput` (`EditAddTransactionViewModel.swift:98,106`).
- **Design token / sheet-reuse names** in Task 4 are marked as "confirm against the codebase" because the exact symbol names are view-layer details the implementer verifies at build time; the logic tasks (1–3) carry no such ambiguity.
- **Cross-kind pending-mutation flush (blocking bug closed):** arming an edit while a delete is pending must finalize the delete, or its removed-from-view rows leak (reappear on reload). Handled in `armUndo` (now `async`, flushes via `commitPending()` first); `scheduleDeletion` deliberately does not flush (delete→delete batching is intentional; edit→delete is safe via `pendingRevert = nil`). Guarded by `armingEditFlushesPendingDelete` in T2.
- **Cleanups:** `input(from:)` no longer takes a double-optional — category edits build their input directly (T3). Bulk-edit tests await the exposed `bulkEditTask` handle instead of `Task.sleep` (T3 + T2 undo test).
