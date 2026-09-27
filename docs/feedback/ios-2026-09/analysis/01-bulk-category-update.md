# P0 Data Corruption: Bulk Category Update Ignores Filter

**Build:** 93 (TestFlight)  
**Feedback ID:** AH1o8htLNPtGWxn-p-ze-dA  
**Date:** 2026-09-21

## Symptom

User filtered the Activity list by expense category "auto", then tapped "Select All" and bulk-updated the category to a newly created one. Instead of updating only the 5 visible "auto" transactions (visible in the screenshot), the app updated **every expense transaction** in the database, destroying their categorization.

Expected: 5 transactions updated (those visible after filtering).  
Actual: ~48 expense transactions updated (entire expense list).

## Root Cause

The bug is a **missing integration of the category chip filter into the filtering pipeline**. The category filter (`selectedCategory`) affects what totals are displayed but does NOT affect `filteredItems`, which drives the selection set.

### Exact Location

**File:** `/Users/gabrielerizzo/Develop/PersonalFinanceTracker/PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`

**The defect spans three code paths:**

#### 1. Category filter does not trigger re-filtering (L30–32)
```swift
var selectedCategory: String? = nil {
    didSet { recomputeDerivedFilterState() }  // ← only updates totals, NOT filteredItems
}
```

When the user taps a category chip, `selectedCategory` is set and `recomputeDerivedFilterState()` is called. **This method does NOT update `filteredItems`.** It only computes:
- `effectiveCategory` (for display)
- `filterCategories` (for menu options)
- Summary totals scoped to the selected category

#### 2. Filtering logic ignores category (L182–206)
```swift
private func doFilterItemBySearchText() async {
    guard !searchText.isEmpty || filters.isActive else {
        self.filteredItems = transactions
        return
    }
    let filtered = await Task.detached(priority: .userInitiated) {
        let dateBounds = filters.resolvedDateBounds()
        return transactions.filter { item in
            let textMatch = searchText.isEmpty || (
                item.note.localizedStandardContains(searchText) ||
                item.amount.description.localizedStandardContains(searchText) ||
                item.category.localizedStandardContains(searchText)
            )
            let filterMatch = filters.matches(item, dateBounds: dateBounds)
            return textMatch && filterMatch
        }
    }.value
    self.filteredItems = filtered
}
```

**The filter logic applies:**
- Search text (note, amount, category name substring)
- `filters` (type/date/amount/recurring chips)

**It does NOT apply:**
- `selectedCategory` (the category chip filter)

The parameter `filters: SearchFilters` has a `categories: Set<String>` field (defined at `TransactionRepository.swift:9`) but it is never populated. The category chip UI directly sets `selectedCategory` on the view model instead.

#### 3. Select All uses unfiltered set (L115–117)
```swift
func selectAllVisible() {
    selectedIDs = Set(filteredItems.map(\.id))
}
```

This method is correctly implemented—it selects only the IDs present in `filteredItems`. **The bug is that `filteredItems` does not include the category filter, so it contains all transactions that match the search/filter chips but no category restriction.**

### Why It Over-Writes

**Path:** User filters "auto" → Select All → Bulk Update Category

1. User filters by "auto" category chip: `selectedCategory = "auto"`
2. `recomputeDerivedFilterState()` runs but does NOT update `filteredItems`
3. `filteredItems` still contains **all transactions** (or all that match search + type/date/amount filters)
4. User taps "Select All": `selectedIDs = Set(filteredItems.map(\.id))` — selects all unfiltered transactions
5. User picks a new category in the bulk editor
6. `bulkSetCategory()` is called, which:
   - Calls `applyBulkEdit(message:newInput:)` (L676)
   - Gets `targets = selectedSnapshots` (L678), which is `transactions.filter { selectedIDs.contains($0.id) }`
   - Loops `repo.update()` for each target (L686–687)
7. Result: **every expense transaction gets the new category**, not just the 5 visible ones

**The selection is correct for the unfiltered dataset.** The bug is the dataset itself: `filteredItems` is incomplete.

## Edge Cases

All bulk actions (delete, amount, note) and all filter types share the same defect:

### 1. Delete under category filter
- Filter by category "Travel", select all, delete → **deletes ALL Travel transactions**, not just visible ones
- **P0 severity**: permanent data loss

### 2. Bulk set amount under category filter
- Filter "Groceries", select all, set amount to €50 → **every Groceries transaction becomes €50**
- Existing amounts are lost

### 3. Bulk set note under category filter
- Same issue for description updates

### 4. Category filter + text search stacking
- Filter by "auto" + search "fuel" → search is applied to all transactions, then select-all is scoped to **all transactions** (not "auto"+"fuel")
- If user expects only "auto"+"fuel" to be selected, they get more

### 5. Category filter + type chip
- Filter by Type=Expense, Category=Auto → Select All → selects all **Expense** transactions, ignoring the auto category
- (Type filter is in `filters.type` and IS applied; category is in `selectedCategory` and is NOT)

### 6. Category filter + date/amount chips
- Filter Expenses + Last 3 Months + Auto category → Select All → selects all Expenses + Last 3 Months (ignoring auto)
- **Inconsistent:** some filters apply, some don't

### 7. Category filter + text search (partial overlap)
- Filter "auto" category, search "fuel" → select all → selects items matching:
  - Text search across all transactions
  - NOT filtered by category
- User sees 2 items on screen (auto + fuel), selects 20 (all matching search, any category)

## Priority Assessment

**P0 — Data Corruption**

Justification: User data is silently overwritten at scale. A single bulk action under any category filter corrupts dozens of transactions. No warning, no confirmation, no undo that catches the over-broad scope (undo restores only the captured prior values, but for the wrong set of transactions). The design spec explicitly requires "Select All scope: selects only the currently visible (searched / filtered) rows, never hidden ones" — this is violated, making the app unusable for bulk-editing mis-categorized imports.

## Open Points

1. **Why wasn't this caught in review?** The test `selectAllVisibleSelectsOnlyFiltered()` (TransactionListViewModelTests.swift, line ~505) tests only text search, not category filter. A test with `vm.filters.type = .expense; vm.selectedCategory = "auto"` would fail.

2. **How long has this been in production?** Bulk category updates were shipped recently (design spec dated 2026-08-10, PR #104 2026-09-21). The category chip filter predates this. Need to determine whether category-filtered select-all existed before bulk edits, or both landed together.

3. **Is `filters.categories` (SearchFilters line 9) dead code?** It exists in the struct but is never populated. Did a refactor split category filtering between `filters.categories` and `selectedCategory`? Reconcile which path is canonical.

4. **Should `selectedCategory` be merged into `SearchFilters`?** Or should `doFilterItemBySearchText()` explicitly handle `selectedCategory` in its filter predicate? The current split makes the filtering logic fragmented.

5. **Does the category filter UI work correctly without bulk edit?** Spot-check: does the app visually hide non-matching transactions and update totals correctly for the selected category (even though the hidden transactions remain in `filteredItems` internally)? If so, the bug is a silent data-layer issue, not a UI one.

6. **Recurring transactions in bulk category-update under category filter:** The design spec says category changes preserve the recurrence link (line 42–47). Verify that a bulk category update under a filter link produces the right transaction set (not all recurring occurrences, just the filtered ones).

---

## Testing Gaps (for regression guard)

Add to `TransactionListViewModelTests.swift`:

```swift
@Test @MainActor func selectAllVisibleFiltersByCategory() async {
    let vm = await makeLoadedVM()
    vm.filters.type = .expense
    await vm.doFilterItemBySearchText()  // Force re-filter after type change
    vm.selectedCategory = "Auto"
    await vm.searchDebounceTask?.value  // Ensure category filter applied
    let autoTransactions = vm.filteredItems
    vm.selectAllVisible()
    #expect(vm.selectedIDs == Set(autoTransactions.map(\.id)))
    #expect(vm.selectedIDs.count < vm.transactions.count)
}

@Test @MainActor func bulkUpdateRespectsCategoryFilter() async {
    let vm = await makeLoadedVM()
    vm.filters.type = .expense
    vm.selectedCategory = "Auto"
    // ... wait for filter to apply ...
    let autoCount = vm.filteredItems.count
    vm.selectAllVisible()
    let autoCategory = vm.availableCategories.first { $0.name == "Groceries" }!
    vm.bulkSetCategory(autoCategory)
    // ... wait for bulk edit ...
    let groceries = vm.transactions.filter { $0.category == "Groceries" }
    #expect(groceries.count == autoCount)  // Only auto transactions became Groceries
}
```

These tests would have caught this bug immediately.
