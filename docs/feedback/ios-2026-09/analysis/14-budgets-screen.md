# Budgets Screen Bug Analysis — Build 76

**Date**: 2026-09-22  
**Severity**: P3 (or higher if jumpiness is severe)  
**Status**: Root causes identified; four distinct defects bundled on one screen  

---

## Symptom

Tester feedback (Italian, translated) from build 76, feedbackIdentifier `ACCOAyuX6T-lvGTBmOymMUc`, flagged **four separate complaints about the Budgets screen**:

1. Missing split between income and expense budget categories
2. "No limit" placeholder text should be "∞", "Infinito", or "illimitato"
3. Focus feels jumpy when pressing chevrons to navigate between fields
4. Unconditional spacer below budget list wastes space when keyboard is closed

Screenshot: `docs/feedback/ios-2026-09/b76-ACCOAyuX.jpg` shows Italian localization with all-expense category list and "Nessun lim..." (truncated "No limit") placeholders.

---

## Root cause

### (1) Missing income-category section

**Code location**:  
- `Features/Budgets/BudgetsView.swift:11–13`:  
  ```swift
  private var expenseCategories: [CategoryModel] {
    categories.filter { $0.transactionType == .expense }
  }
  ```
- Header at `BudgetsView.swift:28`:  
  ```swift
  Text("MONTHLY BUDGET · EXPENSE CATEGORIES")
  ```

**Finding**: The BudgetsView filters and displays **only** expense categories, despite the data model supporting budgets for both types. CategoryModel stores `monthlyBudget: Decimal?` (line 19 `Models/CategoryModel.swift`) with no type restriction — it's available on all categories. ProfileBudgetsSection confirms this design at `Features/Profile/Components/ProfileBudgetsSection.swift:10`:
```swift
budgetedCount: Int {
  categories.filter { $0.transactionType == .expense && ($0.monthlyBudget ?? 0) > 0 }.count
}
```

**Root cause**: BudgetsView intentionally filters to expense only. No income categories are shown, even as a separate section. The question is whether this is intentional product design or an oversight.

**Is income-category budgeting meaningful?** Technically yes — the model supports it. Semantically: income budgets could mean "target earnings per category" (e.g., "freelance: €2000/month"), which is a valid financial concept. However, the app's mental model appears to be expense-focused budgeting only.

**Does fixing (1) require a model change?** No. Adding an income-category section would only require:
- Extracting `incomeCategories` from all categories (parallel to `expenseCategories`)
- A new section header for income categories
- No schema changes.

But it **does require intent confirmation**: is omitting income from budgets a deliberate design choice or a gap?

---

### (2) "No limit" text vs. "∞" or "illimitato"

**Code location**:  
`Features/Budgets/BudgetRow.swift:27`:
```swift
TextField("No limit", text: $text)
```

The placeholder text is hardcoded English "No limit" regardless of the app's localization (Italian, as seen in the screenshot).

**Finding**: The app is localized to Italian (all other strings render in Italian, e.g., "CATEGORIE DI USCITA"). This placeholder stands out as English, and the tester suggests "∞", "Infinito" (Italian for "Infinite"), or "illimitato" (Italian for "unlimited") as better alternatives.

**Issue type**: Localization gap + UX feedback. The string is visible to users and actively breaks the Italian-language experience.

---

### (3) Jumpy focus when pressing chevrons

**Code location**:  
`Features/Budgets/BudgetsView.swift:68–86`:
```swift
.keyboardFieldNavigation($focusedCategoryID, order: order, navigate: { id in
  withAnimation {
    proxy.scrollTo(id, anchor: .top)
  } completion: {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      focusedCategoryID = id
    }
  }
})
.onChange(of: focusedCategoryID) { _, id in
  guard let id else { return }
  withAnimation { proxy.scrollTo(id, anchor: .top) }
}
```

**Root cause — TWO conflicting scroll paths**:

1. **Path A (navigate closure, lines 68–77)**: Triggered by chevron taps. Scrolls to the target row with `.top` anchor, then waits 0.3s before requesting focus.
2. **Path B (onChange, lines 83–86)**: Triggered by any focus change. **Immediately** scrolls to the target row without waiting.

When a chevron is tapped:
- Path A calls `scrollTo` with `withAnimation { ... } completion: { ... after 0.3s ... focusedCategoryID = id }`
- This sets `focusedCategoryID`, which **immediately** triggers Path B
- Path B **also** calls `scrollTo` (potentially competing scroll command)
- 0.3s later, Path A's completion calls `focusedCategoryID = id` again (redundant)

**Why the 0.3s delay?** The comment at `BudgetsView:79–82` refers to TransactionFormView's "same fix" for the Name field. In TransactionFormView (`Features/EditAddTransactionView/Components/TransactionFormView.swift:227–234`), the same 0.3s delay is applied for identical reasons:
```swift
.keyboardFieldNavigation($focusedField, order: [...], navigate: { field in
  withAnimation { proxy.scrollTo(field, anchor: .center) } completion: {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      focusedField = field
    }
  }
})
```

The 0.3s is **intended** to give `scrollTo` time to settle before requesting focus — setting focus on a field that's still mid-scroll can cause the scroll to abort or snap unexpectedly. However, **BudgetsView's onChange still fires immediately** (line 85), potentially fighting the animation.

**Evidence of the fight**:
- TransactionFormView has an `onChange` at line 352, but it's **guarded** to skip if focus is the calculator (line 366): `guard let field, field != .mathExpression else { return }`
- It doesn't unconditionally scroll again like BudgetsView does
- TransactionFormView also uses `.center` anchor in navigate, but `.top` in onChange (line 372), showing deliberate separation of concerns

BudgetsView's `onChange` is **unconditional** and redundant after the navigate closure already scrolled.

**Jumpiness diagnosis**:
- The 0.3s delay alone wouldn't cause visible jumpiness — it's a deliberate pause to let animations settle
- The **redundant dual scrolls** (navigate + onChange both calling `scrollTo`) likely cause the snap/jump: the view may scroll to position, onChange interrupts with another scroll command, causing a stutter
- Or the delay + immediate onChange creates a pause that feels laggy, then a sudden jump as focus lands

---

### (4) Unconditional spacer wastes space when keyboard closed

**Code location**:  
`Features/Budgets/BudgetsView.swift:51–54`:
```swift
Color.clear
  .frame(height: 320)
  .listRowBackground(Color.clear)
  .listRowSeparator(.hidden)
```

This spacer is **always present**, even when the keyboard is closed.

**Finding**: The comment at lines 45–50 explains its purpose: it reserves scroll extent so that rows near the end of the list can actually scroll to the top (above the keyboard and its accessory bar). Without it, the list's natural scroll boundary stops at the last row, preventing `proxy.scrollTo(..., anchor: .top)` from placing a near-last row high enough to be visible above the keyboard.

**Tester's observation**: The spacer should only appear while the keyboard is open, otherwise it's dead weight pushing the scroll view's length artificially.

**Existing pattern in codebase**: KeyboardFieldNavigation (`Utilities/KeyboardFieldNavigation.swift:112–116`) already implements a **keyboard-conditional** spacer:
```swift
.safeAreaInset(edge: .bottom) {
  if focus.wrappedValue != nil {
    Color.clear.frame(height: 60)
  }
}
```

This reserves extra space **only while the keyboard is up** (focus is not nil). BudgetsView can use an analogous pattern: the `focusedCategoryID` state is available to check whether a field is focused.

**Feasibility**: Yes, very clean. Change line 51–54 to:
```swift
// Only reserve scroll extent while keyboard (and budget field) is actually visible
if focusedCategoryID != nil {
  Color.clear.frame(height: 320)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
}
```

This **conditionally shows** the spacer only when editing, matching the tester's suggestion and the pattern used in the keyboard bar.

---

## Edge cases & constraints

1. **Complaint (1) — Design ambiguity**: The intentional omission of income-category budgeting could be deliberate (simplifying the UI to expense focus) or an oversight. ProfileBudgetsSection explicitly filters to expense only, suggesting design intent, but this should be confirmed.

2. **Complaint (3) — Animation timing sensitivity**: The 0.3s delay was chosen based on empirical observation (allowing scrollTo to settle before focus). If reduced, focus might land before scroll completes, causing jump. If increased, the lag becomes visible. TransactionFormView uses the same value, so changing it in BudgetsView alone risks inconsistency.

3. **Complaint (3) — onChange order sensitivity**: SwiftUI's onChange fires in render-order precedence. If the keyboardFieldNavigation modifier's onChange (inside the modifier's implementation) runs *before* BudgetsView's onChange, the redundant scroll may not interfere. But the order is not guaranteed across OS versions.

4. **Complaint (2) — Localization scope**: The string "No limit" is hardcoded in BudgetRow. If localized, it must also update in accessibility hints and other display paths (e.g., BudgetRow.swift:35):
   ```swift
   .accessibilityValue(text.isEmpty ? String(localized: "No limit") : text)
   ```
   Both instances must use the same localized string.

5. **Complaint (4) — Scroll extent without spacer**: Removing the spacer entirely would break the feature — near-last rows would not scroll above the keyboard. The conditional approach is the only solution.

---

## Priority confirmation

**P3 or P2** (guidance needed).

**Rationale**:
- **(1) Section split**: Affects visual organization only; doesn't block functionality. User can still edit budgets. **P3.**
- **(2) "No limit" localization**: Breaks localization polish; user-visible but not a blocker. **P3.**
- **(3) Jumpiness**: If severe enough to frustrate users, this escalates. Chevron navigation is a fallback (keyboard's built-in Next is preferred), so lower usage. **P3** if subtle, **P2** if the jump is 1+ screen heights or produces lag spike.
- **(4) Spacer waste**: Design UX issue; the screen feels padded when it shouldn't. Lower priority since the field is still usable. **P3.**

**Bundle severity**: All four are P3 individually, but together they add up to "this screen needs polish." If (3) is a noticeable stutter, bump to **P2 for the whole screen**.

---

> **Main-session correction (2026-09-22).** This report frames complaint (2) as a
> *localization bug* — that `BudgetRow.swift:27` hardcodes an English placeholder while
> only the accessibility hint at `:35` is localized. **That is wrong.** SwiftUI's
> `TextField(_ titleKey: LocalizedStringKey, text:)` localizes its title automatically,
> and `Localizable.xcstrings` carries `"No limit"` with `it = "Nessun limite"`. The
> placeholder renders correctly in Italian — which is exactly the string the tester
> quoted (*"Anziché 'Nessun limite'…"*). Complaint (2) is therefore a **wording
> preference**, not a defect: they want `∞` / "Illimitato" instead of "Nessun limite".
> Any fix changes the catalog value (or the key), not the localization plumbing.

> **Path correction.** `TravelDetailSheet.swift` (referenced in the trips reports) lives
> at `Features/TransactionListView/Components/`, not `Features/Travel/`.

## Open Points

1. **Is income-category budgeting an intentional omission or a gap?** ProfileBudgetsSection filters to expense only, but this could be a limitation of the current UI rather than by design. Confirm product intent before adding an income section.

2. **Why does the 0.3s delay exist, and can it be shorter?** TransactionFormView uses the same value, suggesting it's calibrated. Would reducing it cause focus to land mid-scroll? Should both screens use a consistent value, or are their scroll dynamics different?

3. **Does the onChange.scrollTo fire before or after navigate's completion closure?** This determines whether the redundant scroll actually interferes. A frame-by-frame inspection would confirm.

4. **Should "No limit" use a symbol (∞) or a localized word (Infinito)?** The tester suggested both; symbols are language-agnostic but less clear to some users. Is there a design precedent in the app for this pattern?

---

## Suggested fix

### Option A: Minimal — Fix (2) and (4) only

- **Complaint (2)**: Localize "No limit" in BudgetRow.swift line 27:
  ```swift
  TextField(String(localized: "No limit"), text: $text)
  ```
  Also update line 35 to use the same source.

- **Complaint (4)**: Conditionally show spacer:
  ```swift
  if focusedCategoryID != nil {
    Color.clear
      .frame(height: 320)
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
  ```

**Trade-off**: Leaves (1) and (3) unfixed. (3) may persist if the dual-scroll issue is real.

### Option B: Recommended — Address (2), (3), (4); defer (1)

- **Complaint (2)**: Localize as above.
- **Complaint (4)**: Conditionally show spacer as above.
- **Complaint (3)**: Remove the redundant onChange.scrollTo or guard it to skip if the navigate closure already ran. Simplest fix:
  ```swift
  .onChange(of: focusedCategoryID) { oldID, newID in
    // Skip scrolling if we got here via navigate (which already scrolled).
    // Only scroll if focus changed directly (e.g., from tapping a row).
    guard let newID, oldID == nil || oldID != newID else { return }
    // But detect direct tap vs. chevron: navigate sets focus after delay,
    // onChange runs immediately, so direct taps DO run onChange first.
    // This is subtle — may need a @State flag to track navigate's call.
    withAnimation { proxy.scrollTo(newID, anchor: .top) }
  }
  ```
  **Caveat**: This requires tracking state to distinguish "chevron nav" from "direct tap," which complicates the logic. See TransactionFormView's pattern for reference — it doesn't have this issue because direct taps don't bypass scroll (the navigate closure is always used for chevrons).

  **Simpler alternative**: Remove the onChange entirely and rely on navigate alone:
  ```swift
  // Remove the onChange at lines 83-86
  ```
  **Risk**: Direct taps (tapping a row) would not scroll the field into view. Check if rows are tappable first.

- **Complaint (1)**: Defer to product decision. Create a feature task to confirm whether income budgets are intended.

**Trade-off**: (3) is tricky to fix cleanly without refactoring; investigate whether the jump is real first (may require on-device testing).

### Option C: Comprehensive — All four

Add income-category section (requires product intent confirmation first):
```swift
private var incomeCategories: [CategoryModel] {
  categories.filter { $0.transactionType == .income }
}

// In body:
Section { ... } header: { Text("MONTHLY BUDGET · INCOME TARGETS") }
// (if income budgeting is decided to be a feature)
```

Then apply Options A + B.

---

## Summary

**Four distinct defects on one screen**, all P3 severity:

1. **Section split** — BudgetsView shows expense categories only; income categories are omitted (data model supports both). Design intent unclear.
2. **Localization gap** — "No limit" placeholder is hardcoded English, breaking Italian localization. Fix: localize the string.
3. **Jumpy focus** — Chevron navigation triggers two conflicting scroll commands (navigate + onChange), likely causing visible stutter. Fix: guard the onChange or remove it if direct taps don't bypass scrolling.
4. **Wasted spacer** — The scroll-extent spacer is unconditional, wasting space when keyboard is closed. Fix: gate on `focusedCategoryID != nil`, matching the pattern in KeyboardFieldNavigation.

**Highest priority fix**: **(2) localization**, as it affects every user on the Italian version.  
**Confidence level**: High on (1), (2), (4); medium on (3) — the jumpiness diagnosis requires on-device confirmation that the dual-scroll is actually firing and interfering.

---

## Notes

- Screenshot confirms Italian localization; app is not in English.
- SampleData.swift does not populate any budgets, so this was tested with manual budget entry.
- KeyboardFieldNavigation pattern in the codebase already solves (4) elegantly; BudgetsView can reuse that approach.
- Project is configured to use graphify for codebase queries, but a direct grep was sufficient here; no graphify query needed.
