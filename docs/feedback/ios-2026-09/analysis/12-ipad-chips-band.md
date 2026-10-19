# iPad Filter Chips Background Band — Build 61

**Date**: 2026-09-22  
**Severity**: P3  
**Status**: Root cause identified, iPad-specific layout

---

## Symptom

The filter chips row (Type, Category, Date, Amount, Recurring) on iPad displays with a visibly darker, solid background band that contrasts with the surrounding gradient background. On iPhone (same build), the chips row blends seamlessly with the page background.

**Evidence**: Tester screenshot (AEwZqtBfav0G9w40_67sjOw) shows a distinct darker rectangular band behind the filter chips. Reference iPad screenshot `docs/screenshots/ipad/dark/02-ledger.png` exhibits the same band; iPhone reference `docs/screenshots/iphone/dark/02-activity.png` shows no such band.

---

## Root cause

**iPad uses a different container layout for the filter chips than iPhone.**

### iPhone (ActivityView)
`PersonalFinanceTraker/Features/TransactionListView/ActivityView.swift:27–30`
```swift
FilterChipsView()
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
```
- FilterChipsView sits inside a `List` `Section` with transparent background
- Inherits the AppBackground gradient from the enclosing NavigationStack (line 206: `.appBackground()`)
- Gradient shows through seamlessly

### iPad (IPadLedgerTable)
`PersonalFinanceTraker/Features/iPad/IPadLedgerTable.swift:254–259`
```swift
private var filterChipsHeader: some View {
    FilterChipsView()
        .background(Color.bg0)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
```
- FilterChipsView is wrapped with an explicit `.background(Color.bg0)` modifier
- Placed in `.safeAreaInset(edge: .top)` (line 87–89)
- `Color.bg0` is a solid colour asset, not the gradient

**The mismatch**: `Color.bg0` is a solid dark colour that does not match the `AppBackground()` gradient. On iPhone's narrow screen, the chips sit in a List row with transparent background. On iPad's wider layout, the solid `bg0` band becomes visually prominent and breaks the visual continuity of the gradient.

---

## Edge cases

1. **Visibility scale**: The band is most noticeable on iPad's wider screen. On iPhone (narrower), the chips row is also shorter and the eye may not notice the discrete background as much—or the band may be outside the main viewport due to list scrolling behaviour.

2. **Light vs. dark appearance**: The solid `bg0` background may be closer to the AppBackground base colour in one theme than the other, affecting how jarring the contrast is. The tester reported this on a dark-mode iPad screenshot.

3. **`.safeAreaInset()` interaction**: The `.safeAreaInset()` modifier clips content to safe area bounds on notched devices. If the filter chips row was intended to bleed to the edge, the inset placement already constrains it; adding a solid background compounds the visual break.

4. **Floating action bar precedent**: The iPad selection bar at the bottom (line 261–277) correctly uses `.background(.bar)`, which is a semi-transparent system material. The filter chips should use a similar material or inherit the gradient, not a solid colour.

---

## Priority confirmation

**P3 is appropriate.**

Rationale:
- iPad-only; iPhone Activity tab is unaffected
- Purely visual polish (no functional impact)
- Users can still interact with chips and filter normally
- The app remains usable and the issue does not block any workflows

Elevated from P4 to P3 because:
- Visibly breaks the app's carefully designed gradient aesthetic
- Appears in a primary navigation surface (filter row)
- Likely fixable with one-line modifier swap (`.background(Color.bg0)` → no background, or use a gradient that matches AppBackground)

---

## Open Points

1. **Why was `Color.bg0` chosen for the iPad filter header?** Was it:
   - Intended to provide visual separation/depth?
   - A copy-paste from a form background pattern that should have been removed?
   - Deliberate to distinguish the filter row from content below?

2. **Should the filter chip row inherit AppBackground gradient on iPad?** If yes, simply removing the `.background(Color.bg0)` line may be sufficient. If no, what background is correct—a translucent material (`.bar`, `.regularMaterial`), or a custom gradient that matches AppBackground?

3. **Why does iPhone ActivityView and iPad IPadLedgerTable use different container patterns for the same view?** Code reuse would suggest a shared data structure or view factory.

---

## Suggested fix

### Option 1: Remove the explicit background (simplest)
**File**: `IPadLedgerTable.swift:256`
**Change**: Delete the `.background(Color.bg0)` line
```swift
private var filterChipsHeader: some View {
    FilterChipsView()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
```
**Trade-off**: The chips row will sit directly on the AppBackground gradient. If visual separation from the table below was desired, this removes it. Check if this looks "floaty" in iPad landscape or on large displays.

### Option 2: Use a system material that matches the app theme
**File**: `IPadLedgerTable.swift:256`
**Change**: Replace with a translucent material
```swift
private var filterChipsHeader: some View {
    FilterChipsView()
        .background(.ultraThinMaterial)  // or .regularMaterial, or .thickMaterial
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
```
**Trade-off**: Adds subtle depth and visual separation while remaining adaptive (light/dark mode automatic). May need testing to confirm the material opacity/tone doesn't create a different mismatch.

### Option 3: Apply AppBackground gradient explicitly
**File**: `IPadLedgerTable.swift:256`
**Change**: Use the same AppBackground view as the page
```swift
private var filterChipsHeader: some View {
    FilterChipsView()
        .background { AppBackground() }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
}
```
**Trade-off**: The filter row and content below both show the same gradient, so there is no visual separation. This matches Option 1 in appearance but makes the intent explicit. May bloat rendering if AppBackground gradient is expensive.

### Option 4: Match iPhone's pattern (most consistent)
**File**: `IPadLedgerTable.swift:254–259`, and potentially `ActivityView.swift`
**Approach**: Refactor IPadLedgerTable to place FilterChipsView in a List Section (like iPhone), not a `.safeAreaInset()`. This unifies the code path and ensures both devices render the chips identically.
**Trade-off**: Larger refactor; requires testing that the iPad layout still works correctly with List vs. safeAreaInset geometry. Worth exploring if code duplication is a concern.

---

## Summary

The iPad Activity screen's filter chips row sits in a `.safeAreaInset()` with an explicit `.background(Color.bg0)` solid colour, while the iPhone Activity screen places the same chips in a List row with transparent background, allowing the AppBackground gradient to show through. The solid background creates a visually jarring band on iPad that breaks the app's visual continuity. P3 severity is justified because it affects the visual polish of a primary UI surface, though it does not impact functionality. The fix is straightforward: either remove the background, use a translucent system material, or apply the AppBackground gradient explicitly.
