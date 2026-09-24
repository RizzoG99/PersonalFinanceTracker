## Symptom

User reports (AG-sJ061VEaIThBZMisMkLU, build 82): searching for "benzina" (Italian: petrol/gas) returns zero results, even though the category exists and is clearly visible in the category grid. Device language: Italian.

Screenshot shows Activity tab with `.searchable` field active, displaying all categories including "Benzina" (highlighted, bottom-right quadrant of grid).

## Which Surface

**Activity tab, free-text `.searchable` search field** (line 164–168, ActivityView.swift). NOT the category picker in add/edit transaction (which has a separate, working filter path).

The searchable binds to `viewModel.searchText`, which drives `doFilterItemBySearchText()` in TransactionListViewModel.

## Root Cause

**File**: `PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift:195–199`

```swift
let textMatch = searchText.isEmpty || (
    item.note.localizedStandardContains(searchText) ||
    item.amount.description.localizedStandardContains(searchText) ||
    item.category.localizedStandardContains(searchText)  // ← BUG: searching raw key, not localized name
)
```

The filter searches `item.category` (the raw English key: `"Gas"`) using `.localizedStandardContains()`. When the user types `"benzina"` on an Italian device, it does NOT match the raw key `"Gas"`.

**Category mapping** (confirmed):
- English key (stored in TransactionModel.category): `"Gas"` (line 41, TransactionCategory.swift)
- Italian display name (Localizable.xcstrings): `"Benzina"`
- Display rendered via `localizedCategoryDisplay` extension (line 62, StringEmojiExtension.swift): `String(localized: String.LocalizationValue(self))`

The asymmetry:
- **What user sees**: "Benzina" (rendered via `localizedCategoryDisplay` everywhere — category grid, transaction rows, chips)
- **What free-text search compares against**: `"Gas"` (the raw key in `item.category`)
- **User types**: `"benzina"`
- **Result**: No match. `"Gas".localizedStandardContains("benzina")` → false

## Does the Chip Filter Share It?

**No.** The chip filter (line 122–123, TransactionRepository.swift) is **correct**:

```swift
// Category filter: if categories set is non-empty, must contain tx.category
if !categories.isEmpty, !categories.contains(tx.category) {
    return false
}
```

This compares raw keys against raw keys (the `categories` set is populated from raw keys when the user selects chips). The chip filter's expected behaviour is pinned in SearchTests (line 42–53): filter operates on raw category keys, and the tests confirm this works.

**The free-text search has a different contract** — it should match against what the user *sees* (the localized name), not the internal storage key. The chip filter does not have this obligation.

## Edge Cases & Related Issues

### 1. **Custom Categories Without Localization**
If a user creates a custom category (e.g., "Personal Splurge"), there is no entry in Localizable.xcstrings. The `String(localized:)` call passes it through verbatim. Searching for "personal" would match correctly because the raw key and display name are the same. **No defect here** — but this creates an inconsistency: built-in categories require knowing the *English* key to search, while custom categories can be searched by their *display* name.

### 2. **Emoji Prefixes in Category Names**
The `removingLeadingEmoji` extension is used when rendering display names in some contexts (e.g., CategoryPieChart.swift, CategoryTrendRow.swift). The raw `item.category` key does NOT include emoji. Searching for the emoji itself (e.g., "⛽" for gas) would not match. This may be intended (treat emoji as decoration only), but the discrepancy is worth noting.

### 3. **English Search on Italian Device**
User on Italian device searches for "Gas" (the English key). Result: **no match**. The raw key is "Gas", but `.localizedStandardContains("Gas")` on an Italian system returns false because the comparison is locale-aware and locale-biased. This is a secondary defect, but a user trying to search in English while using an Italian device cannot fall back to the English category name.

### 4. **Case Sensitivity**
`.localizedStandardContains()` is case-insensitive, so "GAS", "gas", "Gas" all match. This is correct.

### 5. **Partial Matches**
`.localizedStandardContains()` matches substrings, so searching for "Ben" should match "Benzina". The defect is not about substring matching — it's about matching against the wrong string (the English key instead of the Italian display name).

## Priority Assessment

**P1 confirmed** — this is a user-facing defect that blocks a common workflow (search by visible name). The user can see the category in the UI but cannot find it via search, which is high-friction and unexpected behaviour. The fix is straightforward (search against `item.category.localizedCategoryDisplay` instead of `item.category`).

**Impact scope**:
- Affects all users on non-English locales who search for built-in category names.
- No impact on chip-based filter (separate path, already correct).
- No impact on custom categories (no localization, so English name = display name).

## Open Points

1. **Search should match on localized display name, not English key** — determine whether this is a one-line fix (`item.category.localizedCategoryDisplay.localizedStandardContains(searchText)`) or whether there are performance/memory implications of computing the localized name during filtering. The name is currently recomputed per-render in the UI; materializing it once during filtering may be preferable.

2. **Does the transaction note search need localization?** — Currently `item.note` is searched as-is, which is correct (notes are free text). No change needed.

3. **Should English key search be a fallback?** — If a user is bilingual and switches between device languages, or has a hybrid German/Italian keyboard, should searching "Gas" still match even on an Italian device? This is a UX design question, not a bug, but it may be worth considering as a future enhancement (search against both the raw key and the localized name).

4. **Transaction picker in add/edit form** — The CLAUDE.md prior finding mentions `CategoryPickerSheet.filtered` (TransactionFormView ~line 718) which does `categories.filter { $0.name.localizedCaseInsensitiveContains(search) }`. This is filtering on `CategorySnapshot.name` (the display name, localized), which is **correct**. Verify that this picker works as expected (it appears to, since no bug was reported for it).

5. **Testability** — The `doFilterItemBySearchText()` method is tested via `TransactionListViewModel.searchText` binding and debounce, but there is no explicit unit test for the category search part. Consider adding a test: `testFreeTextSearchMatchesCategoryDisplayName_Italian()` to pin this behaviour once fixed.
