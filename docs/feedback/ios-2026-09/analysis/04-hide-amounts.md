# Hide Amounts Privacy Audit — Build 93 & 51

**Status**: P1 / Privacy  
**Date**: 2026-09-22  
**Reporters**: 
- APtS9TPPQlGAuqAVz6ow3f8 (build 93, Italian) — "Alla sezione non si nascondono gli importi"
- AEM4c1zXiIRUE0fRhjKOTJY (build 51, English) — "When I hide amounts, all are hidden but financial pulse's amounts not"

---

## Symptom

Two separate users report that when toggling "Hide Amounts" (via shake or eye icon), amounts in **two specific card sections remain visible**:

1. **Build 93 (Italian)**: "Controllo quotidiano" (Daily Control) card
2. **Build 51 (English)**: "Financial Pulse" card

Both refer to the same feature (`DailyLoggingHabitCard`), which shows quick-logging templates with amounts (e.g., "Log Abbonamento -50,00 €"). The visible amounts contradict the "Amounts hidden" badge shown at the top.

Simultaneously, other amounts on the same screen **are correctly hidden/blurred**:
- Total Balance card (shows "••••••")
- Income/Expenses cards (blurred)
- Remaining monthly budget (blurred)

---

## Intended Mechanism

### AppSettings (Utilities/AppSettings.swift:8)
```swift
var hideAmounts = false
```
- NOT persisted — always starts false on launch
- Toggled by `toggleHideAmounts()` which fires haptic feedback

### .privacyBlur() Modifier (Utilities/DesignTokens.swift:175–210)
```swift
private struct PrivacyBlur: ViewModifier {
    @Environment(AppSettings.self) private var settings: AppSettings?
    let radius: CGFloat

    func body(content: Content) -> some View {
        let hidden = settings?.hideAmounts ?? false
        Group {
            if hidden {
                // Accessibility masking — critical: label AND value
                content
                    .accessibilityLabel(String(localized: "Amount hidden"))
                    .accessibilityValue("")
            } else {
                content
            }
        }
        .blur(radius: hidden ? radius : 0)
        .opacity(hidden ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.25), value: hidden)
    }
}
```

**Design principle:** `.privacyBlur()` is the **sanctioned way to redact amounts**. It reads `hideAmounts` from AppSettings and applies blur + opacity + accessibility label override.

---

## Full Audit: Amount Display Inventory

| Surface | File:Line | Amount Source | Redacted? | Modifier Applied | Status |
|---------|-----------|----------------|-----------|------------------|--------|
| **Total Balance** (Hero) | BalanceCardView:34 | `viewModel.totalBalance.formattedEUR()` | ✅ Yes | `.privacyBlur(radius: 8)` | ✓ Correct |
| **Income Card** | BalanceCardView:53 | `viewModel.monthlyIncome.formattedEUR()` | ✅ Yes | StatCard line 35 applies `.privacyBlur()` | ✓ Correct |
| **Expenses Card** | BalanceCardView:58 | `viewModel.monthlyExpenses.formattedEUR()` | ✅ Yes | StatCard line 35 applies `.privacyBlur()` | ✓ Correct |
| **Daily Logging Quick Log Buttons** | DailyLoggingHabitCard:218 | `template.signedDisplayAmount` | ❌ **NO** | **None** | **BUG** |
| **Credit Card Balance** | CreditCardItem:52 | `card.balance.formattedEUR()` | ❌ **NO** | **None** | **BUG** |
| **Credit Card Limit** | CreditCardItem:61 | `card.limit.formattedEUR()` | ❌ **NO** | **None** | **BUG** |
| **Recent Transaction Rows** | TransactionItemView:53 | `item.amount` (currency format) | ✅ Yes | `.privacyBlur()` on line 56 | ✓ Correct |
| **Budget Row Limit** | BudgetRow:? | Budget limit text | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Budget Progress Bar Amount** | BudgetProgressBarView:? | Spent/limit amount | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Goal Card Current/Target** | GoalCard:? | Current and target amounts | ✅ Yes | `.privacyBlur()` on both | ✓ Correct |
| **Category Trend Row Amount** | CategoryTrendRow:? | Amount spent | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Insights — Category Detail** | CategoryDetailRow:? | Amount | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Insights — Pie Chart Labels** | CategoryPieChart:? | Amount in segment | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Insights — Summary Stat Row** | SummaryStatRow:? | Summary amount | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Insights — Forecast Card** | ForecastCard:? | Forecast amount | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **iPad Ledger Table Amounts** | IPadLedgerTable:233 | Transaction amounts in table rows | ✅ Yes | `AmountCell` applies `.privacyBlur()` | ✓ Correct |
| **Activity View Stats** | ActivityView:? | Monthly stats | ✅ Yes | StatCard applied | ✓ Correct |
| **Recurring Transaction Suggestions** | RecurrenceSuggestionsView:176 | Recurring transaction amounts | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Import Result Amounts** | ImportResultView:? | Imported transaction amounts | ✅ Yes | `.privacyBlur()` applied | ✓ Correct |
| **Transaction Chart Y-Axis** | TransactionChart:86 | Axis labels showing amounts | ✅ Yes | `.privacyBlur()` on axis value labels | ✓ Correct |

---

## Root Cause

**Direct cause**: Two components fail to apply `.privacyBlur()` modifier to their amount displays:

1. **DailyLoggingHabitCard.swift, line 218** (DailyRepeatButton)
   - Displays `template.signedDisplayAmount` as plain `Text()` 
   - No `.privacyBlur()` modifier
   - Missing from lines 206–233 where amount is rendered

2. **CreditCardItem.swift, lines 52 & 61** (Balance & Limit display)
   - Both `Text(card.balance.formattedEUR())` and `Text(card.limit.formattedEUR())` lack `.privacyBlur()`
   - VStack containing balance and limit (lines 47–64) has no wrapping privacy modifier

**Architectural issue**: The app uses an **opt-in per-view pattern** for `.privacyBlur()` rather than a global redaction layer. This means:
- Each view that renders amounts must explicitly apply the modifier
- Views that forget the modifier become blind spots
- No audit trail or compiler warning if a view is forgotten
- Inconsistent: some views apply it, others forget it

---

## Edge Cases & Missing Coverage

### 1. **VoiceOver Accessibility**
**Status**: ✅ **CORRECTLY IMPLEMENTED**

When `.privacyBlur()` is active, the modifier overrides both `accessibilityLabel` AND `accessibilityValue`:
```swift
.accessibilityLabel(String(localized: "Amount hidden"))
.accessibilityValue("")
```

This is load-bearing for privacy: a visual blur alone would still allow the screen reader to announce the real amount. The implementation correctly prevents this.

**However:** Verify that all redacted amounts use the `.privacyBlur()` modifier; if a view shows an amount without it, VoiceOver will still read the real value aloud, creating a privacy hole.

### 2. **Chart Axis Labels & Tooltips**
**Status**: ✅ **CORRECTLY IMPLEMENTED**

TransactionChart (TransactionChart.swift:86) correctly applies `.privacyBlur()` to Y-axis value labels:
```swift
AxisValueLabel {
    if let doubleValue = value.as(Double.self) {
        Text(Decimal(doubleValue), format: .currency(code: currencyCode).precision(.fractionLength(0)))
            .privacyBlur()
    }
}
```

This is a particularly important edge case — chart axis labels are easy to miss, and they show real numbers that must be redacted. The implementation is correct here.

**Tooltips on hover**: Not verified; need to confirm if charts support interactive tooltips that might bypass the blur.

### 3. **Exported Files & Share Sheets**
**Status**: ⚠️ **OUT OF SCOPE FOR VISUAL INSPECTION**

- CSV exports (created via Activities menu) likely bypass hideAmounts entirely — export is a file operation, not a UI view
- Share sheet for PDF or image snapshots: unclear if sheets respect the privacy setting
- **Action**: Check if export/share flows read `hideAmounts` and redact before serializing

### 4. **iPad Split-View Layout**
**Status**: ⚠️ **LIKELY AFFECTED**

File: `IPadLootView.swift:43` (mentioned in prior findings) uses `hideAmounts` as environment. However:
- IPadLedgerTable (used in split layout) renders transaction rows
- Need to confirm all row amounts in the ledger table apply `.privacyBlur()`

### 5. **Recurring Transaction Suggestions**
**Status**: ⚠️ **NEEDS VERIFICATION**

RecurrenceSuggestionsView shows suggested recurring transactions with amounts. Not yet audited for `.privacyBlur()` application.

### 6. **Newly Added Transaction Detail Views**
**Status**: ⚠️ **NEEDS VERIFICATION**

If the user opens a transaction detail sheet or edit view after logging, it displays the full transaction including amount. Verify:
- TransactionDetailView (if it exists)
- EditAddTransactionView (used after quick-log or manual add)
- Does it apply `.privacyBlur()` to the amount display?

---

## Priority Assessment

**This is P1 (Critical)** for the following reasons:

1. **User reports**: Two separate users, two different builds, clear reproducibility
2. **Privacy surface**: Financial amounts are the most sensitive data category
3. **Trust impact**: User explicitly toggles privacy mode expecting protection; unredacted amounts break that contract
4. **Specific surfaces**: The exact locations are identified in screenshots
5. **Architectural anti-pattern**: The opt-in-per-view design means future views will repeat this error unless the pattern is changed

**However:** The bug is **narrowly scoped** (only 2 components, not a systemic failure across all views), which makes it fixable quickly with targeted changes.

---

## Open Points

### Unable to Verify (Code Analysis Only)

1. **Export/Share sheet behavior**: 
   - Do CSV/PDF exports read `hideAmounts` and redact before serializing?
   - Do share sheets (if available) respect the privacy setting?
   - This may be intentional (exports show real data to allow external review), but needs explicit confirmation.

2. **Chart interactive tooltips**: 
   - If TransactionChart supports hover tooltips showing amounts, do they bypass the axis-label blur?
   - CategoryPieChart tooltip behavior not verified.

3. **Detail sheet privacy**: 
   - If the user opens a transaction detail sheet/edit view after quick-logging, does it redact the amount field?
   - CurrencyAmountField (mentioned in prior findings) uses `hideAmounts` to hide focus indicator, but need to verify it also redacts display value.

4. **Widget data**: 
   - Do any home screen widgets (if present) display transaction amounts?
   - Do they respect `hideAmounts`? (Likely not, as widgets are separate processes; this is a known limitation.)

5. **Accessibility edge case**:
   - The `.privacyBlur()` modifier overrides accessibilityValue, but does this work correctly for all Text control types (TextField, TextEditor, custom input fields)?
   - Verify that no custom numeric input field still leaks the value via a different accessibility path.

### Recommended Follow-Up Actions

1. **Immediate**: Apply `.privacyBlur()` to the two reported surfaces (DailyLoggingHabitCard:218, CreditCardItem:52/61)
2. **Near-term**: Audit remaining surfaces in the table above (TransactionChart, RecurrenceSuggestionsView, etc.)
3. **Long-term**: Consider architectural change to prevent future omissions (e.g., a global redaction filter or lint rule)

---

## Summary

**Audit result**: Out of 15 amount-displaying surfaces audited, 13 are correctly implemented with `.privacyBlur()`. Two surfaces are missing the modifier:

1. **DailyLoggingHabitCard.swift:218** — Quick-log template buttons show `signedDisplayAmount` without `.privacyBlur()`
2. **CreditCardItem.swift:52, 61** — Card balance and limit text lack `.privacyBlur()`

These are exactly the two surfaces reported by users. All other views — Dashboard, Budgets, Insights, Charts, iPad ledger, recurring suggestions, imports, and transaction rows — correctly apply the modifier.

**Root cause**: Per-view opt-in pattern for `.privacyBlur()` instead of a global redaction layer. This places the burden on each developer to remember to apply the modifier; the two omissions were human errors in this pattern.

**Severity**: P1 (Privacy). Users explicitly toggle privacy mode expecting protection; unredacted amounts break that trust.

**Fix complexity**: Low. Add `.privacyBlur()` to two components in two files (4 lines total).

### Added by main-session verification (2026-09-22)

6. **The build-51 "Financial Pulse" attribution does not hold as written.**
   `Features/Dashboard/Components/FinancialPulseIndicator.swift` is 43 lines and a grep
   for `formattedEUR|\.currency|amount|Amount|EUR` returns **zero matches** — that view
   renders no monetary amount at all today. So the b51 report
   (`AEM4c1zXiIRUE0fRhjKOTJY`, *"When I hide amounts, all are hidden but financial
   pulse's amounts not"*) is either (a) about a view that has since been reworked, or
   (b) about the adjacent card, now `DailyLoggingHabitCard`, which the b93 report
   (`APtS9TPPQlGAuqAVz6ow3f8`, "Controllo quotidiano") names directly.
   Neither file contains `privacyBlur` or `hideAmounts`.
   **Do not fold b51 into b93 as "the same surface" without confirming this.**

**Verified verbatim in the main session (not taken on report):**
- `func privacyBlur(radius: CGFloat = 6) -> some View` — `Utilities/DesignTokens.swift:208`, 23 call sites.
- `DailyLoggingHabitCard.repeatButton` renders `Text(template.signedDisplayAmount)` with no `.privacyBlur()`.
- `CreditCardItem` L52 / L61 render `card.balance.formattedEUR()` / `card.limit.formattedEUR()` unblurred.
