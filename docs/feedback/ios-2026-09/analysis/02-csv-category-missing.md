# CSV Import: Category name without backing CategoryModel

**Build**: 93  
**Feedback ID**: ADdR89AM80RkY0p3FiCAmO0  
**Status**: P1 – confirmed root cause

## Symptom

User imported transactions via CSV/Excel. During import, they requested creation of a new category named "auto". The resulting transaction displays "Auto" in the Activity list but shows **no category selected** when opening its detail view. Additionally, Settings → Categories does **not list "Auto"** at all.

The transaction was successfully created with a freeform category name but **without a corresponding CategoryModel persisted to the database**.

## Root Cause

The bug is a **race condition / matching failure in the category creation path** during CSV import, split across two files:

### Primary Issue: Category Matching Failure

**File**: `PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`  
**Lines**: 808–812 in `confirmImport()`

```swift
if let catSnapshot = updatedCategories.first(where: {
    $0.name == createdDraft.name && $0.transactionType == createdDraft.type
}) {
    newCategoryPersistentIds[csvCatName] = catSnapshot.persistentId
}
```

**The failure mode**: After creating a new CategoryModel (line 783), the code fetches updated categories (line 794). It then attempts to find the just-created category in the fetched list using an **exact name + type match**. If this match fails—catSnapshot remains nil—the `csvCatName` is **never inserted** into `newCategoryPersistentIds`.

**Consequence**: In Step 4 (lines 836–848), when linking transactions to categories, the code tries to look up the CSV category name in `newCategoryPersistentIds`:

```swift
for i in updatedInputs.indices {
    if updatedInputs[i].categoryPersistentId == nil,
       let persistentId = newCategoryPersistentIds[updatedInputs[i].category] {  // ← lookup fails
        updatedInputs[i] = TransactionInput(…, categoryPersistentId: persistentId)
    }
}
```

If the name is not in the dictionary, the transaction is inserted **with only the freeform category String and no categoryPersistentId**.

### Secondary Issue: Detail View Displays Nothing

**File**: `PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift`  
**Lines**: 140–147 in `setTransactionViewModel()`

```swift
if let catId = editingItem?.categoryId {
    selectedCategory = availableCategories.first { $0.persistentId == catId }
}
```

When opening a transaction for editing, the ViewModel tries to find the category by `categoryId` (which is nil for the orphaned transaction). The lookup fails, and `selectedCategory` remains nil, so the category picker displays **no selection**.

### Why the Match Fails

The most likely causes:

1. **Whitespace mismatch**: The user entered "auto" in the CSV or import dialog; the app trimmed it (line 39 of `ImportCategorySetupSheet.swift`), but the fetched category name has different whitespace.  
2. **Case sensitivity**: Although `isDuplicate` in `CategoryNameValidator` does case-insensitive comparison (seen in `ImportCategorySetupSheet.swift:53`), the snapshot matching at line 809 does **exact case-sensitive comparison**.  
3. **Type mismatch**: The category's inferred type does not match the actual type assigned during creation.  
4. **Fetch race**: The category was created but not yet visible when `fetchCategories()` is called (line 794), though SwiftData should handle this atomically.

### Transaction Model Structure

**File**: `PersonalFinanceTraker/Models/TransactionModel.swift`  
**Lines**: 16–23

```swift
var category: String                           // ← Freeform category name
var idCategory: String?
@Relationship(deleteRule: .nullify)
var categoryModel: CategoryModel?               // ← Should point to CategoryModel, but is nil
```

Transactions store both a freeform `category: String` and an optional `@Relationship` to `CategoryModel`. This dual structure allows a transaction to exist with only the String—the orphaned state reported here.

## State on Current HEAD

**Commit 83bc9db** ("Teach the CSV importer to recognise category names it was missing", Sep 18, 2026) **does NOT fix this bug**. That commit only replaced the hardcoded `"__new__"` sentinel with `CategoryAutoMapper.newSentinel` (a refactor, no logic change).

The faulty matching code at lines 808–812 remains **unchanged and active on HEAD**. The bug **survives on current main**.

## Edge Cases

### 1. **Duplicate Category Name with Different Case**

- User imports CSV with "Auto" and "AUTO".
- Both are treated as separate categories to create (case-sensitive dedup in import UI: line 53 uses `isDuplicate` which is case-insensitive).
- Actually, `isDuplicate` would catch "Auto" vs "AUTO" and show "A category with this name already exists", so both cannot be created in the same import.
- However, if the user creates "Auto" first, then in a later import creates "AUTO", the second import would create a second category (case-insensitive collisions are not prevented across imports).

### 2. **Income vs. Expense Type Mismatch**

- CSV has a transaction marked as Income with CSV category "Salary".
- Import dialog suggests creating Income + "Salary".
- During import, if the category is somehow tagged Expense (e.g., type inference bug), the fetch-and-match at line 809 fails: `$0.transactionType == createdDraft.type` is false.
- Transaction gets: `category: "Salary"`, `categoryModel: nil`, `categoryId: nil`.
- Editing the transaction shows no category selected.
- **Settings → Categories** lists no "Salary" (or lists a different Expense "Salary" if one was auto-created).

### 3. **Whitespace in Category Name**

- CSV has "Car Fuel" (with regular space).
- User edits in dialog to "Car  Fuel" (two spaces) by mistake.
- `draft.name = trimmedName` (line 121 of `ImportCategorySetupSheet.swift`) removes leading/trailing whitespace but **not interior double spaces**.
- CategoryModel is created with name "Car  Fuel".
- Fetch returns categories, but the match tries `$0.name == "Car  Fuel"` (the draft).
- If the CSV data had "Car Fuel" (single space), the lookup at line 838 (`category` field on TransactionInput) is "Car Fuel" (single space).
- The transaction is inserted with `category: "Car Fuel"` but no categoryPersistentId.
- Meanwhile, a CategoryModel "Car  Fuel" (double space) sits in Settings → Categories, never used.

### 4. **Emoji in Category Name**

- CSV has "🚗 Auto".
- `ImportCategoryDraft` strips leading emoji on line 34: `let strippedName = csvCategory.removingLeadingEmoji.trimmingCharacters(in: .whitespaces)`.
- Draft's suggested name is "Auto" (emoji removed).
- User confirms creation: CategoryModel "Auto" is inserted.
- CSV category in the transaction is still "🚗 Auto".
- Lookup at line 838: `newCategoryPersistentIds["🚗 Auto"]` → not found (key is "🚗 Auto", not "Auto").
- Transaction inserted with `category: "🚗 Auto"`, `categoryModel: nil`.

### 5. **What Happens If User Manually Creates the Category Later**

- Transaction exists with `category: "Auto"`, `categoryId: nil`.
- User goes to Settings → Categories → New and creates "Auto" category.
- The transaction's `categoryId` is still nil; it does not auto-link.
- The transaction remains orphaned.
- But now a real CategoryModel "Auto" exists, so deleting the transaction or editing it would let the user pick from two sources of truth (the freeform string vs. the CategoryModel).

## Priority Reassessment

**Confirmed P1** — Data corruption vector.

**Rationale**:
- Affects any CSV import where a user creates a new category.
- The user sees feedback (category name displays in list view) suggesting the operation succeeded, but internal state is corrupted.
- When editing the transaction, the category picker shows nothing, breaking the user's mental model that the transaction has a category.
- Settings → Categories does not show the "category", violating system consistency.
- Cascading: If user creates the category manually later, a second CategoryModel can exist alongside the orphaned transaction string.
- **User-facing symptom severity**: The import appears to succeed but key data is missing from the detail view.

This is a **silent, undetected data loss** during the most critical import operation.

## Open Points

1. **Root cause of matching failure in production**: Was it whitespace, case, type mismatch, or a race condition? The matching logic appears sound (exact name + type), but one of these must have triggered on the user's device. A device-side assertion or logging of the createdDraft name + type vs. fetched snapshot names would isolate the exact failure.

2. **Frequency**: Is this reproducible on all imports of new categories, or only under specific conditions (race, certain category names, certain CSV formats)?

3. **Why is the freeform String field still used**: TransactionModel has both a `category: String` and a `categoryModel: CategoryModel?` relationship. The String is never validated against existing CategoryModels. Was this designed for data migration or legacy imports, or is it cruft?

4. **Why no validation on insert**: The `repo.addBatch(toInsert)` call (line 880) accepts `TransactionInput` objects. Does the repository or SwiftData validator enforce that a transaction with `categoryPersistentId == nil` must not have a non-empty `category` String? If so, why did the insert succeed?

5. **Test coverage**: Are there tests for CSV import with category creation? If yes, why wasn't this caught? If no, adding one would be the minimum prevention.

## Recommended Fixes

1. **Immediate**: After creating a category (line 783), before fetching (line 794), wait for the transaction to be committed, or refetch with a small delay, or assert on a fresh fetch that the category name now exists.

2. **Defensive**: If the name-match lookup fails, log a warning and use a fallback (e.g., search by category name only, case-insensitive, with type as a tie-breaker).

3. **Validation**: Add a constraint or validator: if `category` String is non-empty, `categoryPersistentId` must be non-nil, or vice versa.

4. **Testing**: Add a test that creates a category during import and verifies that the resulting transaction's `categoryPersistentId` is set and matches the persisted category.

5. **Schema cleanup**: Decide if the freeform `category: String` field is still needed. If not, migrate it away and rely solely on the `categoryModel` relationship.
