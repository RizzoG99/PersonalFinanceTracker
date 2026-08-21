# "Add another transaction" toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toggle to the Add-transaction sheet that keeps the sheet open after a save (blanking the form, re-focusing Amount, confirming with a haptic + toast) so the user can log several transactions in a row.

**Architecture:** Reset-in-place — on save with the toggle on, call the view model's existing `resetForm()` instead of `dismiss()`. No dismiss/re-present, so no coordination with `MainTabView`. A focus-token forces the `CurrencyAmountField` to clear its private `displayText` and re-raise the keypad. Feedback is a native `.sensoryFeedback` haptic plus a `ToastBanner` overlay owned by the sheet.

**Tech Stack:** SwiftUI, `@Observable` view models, Swift Testing (`@Test`/`#expect`), iOS liquid-glass SDK.

**Spec:** `docs/superpowers/specs/2026-08-08-add-another-transaction-toggle-design.md`

## Global Constraints

- Swift Testing only (`@Test`, `#expect`, `#require`), NOT XCTest. `@testable import PersonalFinanceTraker`.
- Build & test via Xcode MCP tools only (`mcp__xcode__BuildProject`, `mcp__xcode__RunSomeTests`) with `tabIdentifier: "windowtab1"` — verify the active tab first. `xcodebuild` is banned.
- All new user-facing strings wrapped in `String(localized: "…")` and added to the string catalog.
- The toggle is **Add-mode only** (`editingItem == nil`) and **session-only** (defaults OFF each sheet open; no persistence — guaranteed for free because a fresh view model is constructed per presentation).
- Expenses/transfers stored as negative `Decimal`; currency handling unchanged (base currency via `resetForm()`).
- Amounts: the amount field renders a private `@State displayText`, not `amount` — clearing the model is not enough to clear the display (see Task 2).

---

## File Structure

- `EditAddTransactionViewModel.swift` — owns the `addAnother` flag; `resetForm()` preserves it (Task 1).
- `CurrencyAmountField.swift` — gains a `focusTrigger` token that forces a focus cycle to clear + re-focus (Task 2).
- `TransactionFormView.swift` — renders the toggle, Add-mode only (Task 3).
- `EditAddTransactionView.swift` — save-flow coordination: error handling, reset-in-place, haptic, toast, token bump (Task 4).
- `EditAddTransactionViewModelTests.swift` — unit tests for the flag/reset (Task 1).

---

### Task 1: `addAnother` flag on the view model

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift`

**Interfaces:**
- Produces: `var addAnother: Bool` on `EditAddTransactionViewModel` (defaults `false`); `resetForm()` leaves `addAnother` unchanged.

- [ ] **Step 1: Write the failing tests**

Append to the `// MARK: resetForm` section of `EditAddTransactionViewModelTests.swift`:

```swift
@Test @MainActor func addAnotherDefaultsToFalse() async throws {
    let vm = makeVM()
    #expect(vm.addAnother == false)
}

@Test @MainActor func resetFormPreservesAddAnother() async throws {
    let vm = makeVM()
    vm.addAnother = true
    vm.transactionName = "Coffee"
    vm.amount = 3
    vm.resetForm()
    #expect(vm.addAnother == true)      // control flag survives across saves
    #expect(vm.transactionName == "")   // form fields still cleared
    #expect(vm.amount == 0)
}

@Test @MainActor func isFormValidIsFalseAfterReset() async throws {
    let vm = makeVM()
    vm.transactionName = "Coffee"
    vm.amount = 3
    vm.selectedCategory = expenseCat()
    vm.resetForm()
    #expect(vm.isFormValid == false)    // blank form can't be re-saved
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Load schemas via ToolSearch (`select:mcp__xcode__RunSomeTests`), then run the three new tests. Expected: `addAnotherDefaultsToFalse` and `resetFormPreservesAddAnother` FAIL to compile (`addAnother` undefined); `isFormValidIsFalseAfterReset` PASSES already (harmless — it locks in the guarantee).

- [ ] **Step 3: Add the property**

In `EditAddTransactionViewModel.swift`, add alongside the other `var` form fields (after `recurrenceInterval`, around line 27):

```swift
    /// When on, saving reopens a blank form in place instead of dismissing, so the
    /// user can log several in a row. Session-only, Add-mode only. Deliberately NOT
    /// touched by resetForm() — it must survive across the sequential saves.
    var addAnother: Bool = false
```

Leave `resetForm()` (lines 189-200) unchanged — it must not reference `addAnother`.

- [ ] **Step 4: Run the tests to verify they pass**

Run the same three tests. Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionViewModel.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Features/EditAddTransactionView/EditAddTransactionViewModelTests.swift
git commit -m "feat: add addAnother flag to EditAddTransactionViewModel"
```

---

### Task 2: `focusTrigger` on `CurrencyAmountField` (clear + re-focus)

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/CurrencyAmountField.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a new initializer parameter `focusTrigger: Int` (default `0`, so existing call sites are unaffected). Bumping the passed value forces the field to clear its display and re-raise the keypad.

**Why this task is separate:** this is where the one real bug lives (spec §3). The field renders a private `@State displayText` that only re-syncs from `amount` on `onAppear`, on `onChange(of: amount)` **guarded by `if !isFocused`**, and on `onChange(of: isFocused)`. In the add-another happy path the keyboard never drops, so `isFocused` stays `true`, the `amount`-change handler bails on its guard, and the field keeps showing the old number after `resetForm()` sets `amount = 0`. Forcing a `false → true` focus cycle re-runs `onChange(of: isFocused)`, which (with `amount == 0`) sets `displayText = ""` — clearing the field and re-presenting the keypad.

- [ ] **Step 1: Add the `focusTrigger` parameter**

In `CurrencyAmountField.swift`, add a stored property and initializer parameter (mirror the existing `shouldAutoFocus` wiring, lines 23 & 36-48):

```swift
    let shouldAutoFocus: Bool
    let focusTrigger: Int
```

```swift
    init(
        label: String = "Amount",
        placeholder: String = "0",
        amount: Binding<Double>,
        currencyCode: Binding<String>,
        shouldAutoFocus: Bool = false,
        focusTrigger: Int = 0
    ) {
        self.label = label
        self.placeholder = placeholder
        self._amount = amount
        self._currencyCode = currencyCode
        self.shouldAutoFocus = shouldAutoFocus
        self.focusTrigger = focusTrigger
    }
```

- [ ] **Step 2: Add the focus-cycle handler**

On the `TextField` (alongside the existing `.onAppear`/`onChange` modifiers, after the `onAppear` block at lines 101-108), add:

```swift
                    .onChange(of: focusTrigger) { _, _ in
                        // Force a focus cycle: the false -> true transition re-runs
                        // onChange(of: isFocused), which (amount == 0 after resetForm)
                        // sets displayText = "" and re-raises the keypad. A bare
                        // `isFocused = true` would be a no-op here — the field is already
                        // focused — leaving the stale number on screen. No `if !isFocused`
                        // guard: the token only bumps on save, never mid-edit.
                        isFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
```

- [ ] **Step 3: Build to verify it compiles**

Load schemas via ToolSearch (`select:mcp__xcode__BuildProject`), then `mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`. Expected: build succeeds; existing `CurrencyAmountField` call sites (which omit `focusTrigger`) still compile via the default.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/CurrencyAmountField.swift
git commit -m "feat: add focusTrigger to CurrencyAmountField for in-place clear + refocus"
```

---

### Task 3: "Add another" toggle in the form

> **Superseded 2026-08-20 — presentation changed.** The in-form `Toggle` + footer
> below shipped as written, then moved twice more:
>
> | Commit | What changed | Why |
> |---|---|---|
> | `c8948d2` | Shipped as written here: labeled `Toggle` + footer caption | this plan |
> | `5c4493c` | Form reordered required-first, category picker compacted to a single-row scroller, "Repeat" moved to a nav-bar toggle, "Add another" moved to a pinned bottom zone, **captions dropped** | keep the *required* Category field reachable above the keyboard |
> | `6b8612a` (PR #35) | Pinned bottom zone deleted; save → nav-bar icon-only checkmark; "Add another"/"Repeat" → keyboard accessory bar as icons | the pinned button kept colliding with the keyboard's own accessory bar (three rejected background/material/card iterations) |
>
> Net effect: the label and footer text below are gone, and neither control
> carries a visible explanation for a first-time sighted user — filed as issue
> #31. Fixed 2026-08-20 not by reverting to this toggle (the layout constraints
> above still hold) but with TipKit tips: a one-time inline `TipView` for the
> keyboard-bar controls (an anchored `.popoverTip()` was tried first and does
> not render from `ToolbarItemGroup(placement: .keyboard)` — verified
> on-device, that bar lives in `UIRemoteKeyboardWindow`, not the app window),
> plus an anchored `.popoverTip()` on the nav-bar checkmark, which works fine
> there. See `TransactionFormTips.swift` and issue #31 for the current state.

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/TransactionFormView.swift`

**Interfaces:**
- Consumes: `viewModel.addAnother` (Task 1).
- Produces: a bound toggle visible only when `viewModel.editingItem == nil`.

- [ ] **Step 1: Add the toggle section**

In `TransactionFormView.swift`, immediately after the `if viewModel.editingItem == nil && viewModel.transactionType != .transfer { … }` recurring section (closes at line 71), add a new section gated on Add-mode:

```swift
                if viewModel.editingItem == nil {
                    Section {
                        Toggle(String(localized: "Add another"), isOn: $viewModel.addAnother)
                    } footer: {
                        Text("Keep this sheet open after saving to log several in a row.")
                    }
                    .appFormSectionBackground()
                }
```

- [ ] **Step 2: Build to verify it compiles**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`. Expected: build succeeds.

- [ ] **Step 3: Add strings to the catalog**

Ensure `"Add another"` and `"Keep this sheet open after saving to log several in a row."` are present in the app's string catalog (`Localizable.xcstrings`), matching how existing form strings are registered.

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/TransactionFormView.swift PersonalFinanceTraker/PersonalFinanceTraker/Localizable.xcstrings
git commit -m "feat: add 'Add another' toggle to transaction form (Add mode only)"
```

---

### Task 4: Save-flow coordination in `EditAddTransactionView`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift`

**Interfaces:**
- Consumes: `viewModel.addAnother` (Task 1), `CurrencyAmountField(focusTrigger:)` — passed **through `TransactionFormView`** (see Step 1), `viewModel.showingErrorAlert`/`errorMessage` (existing).
- Produces: the working feature.

**Note on the focus-token wiring:** `CurrencyAmountField` is instantiated inside `TransactionFormView`, not `EditAddTransactionView`. Thread the token through: add a `focusTrigger: Int` parameter to `TransactionFormView` and forward it to the `CurrencyAmountField` at `TransactionFormView.swift:10-16`. `EditAddTransactionView` owns the `@State` and passes it down.

- [ ] **Step 1: Thread `focusTrigger` through `TransactionFormView`**

In `TransactionFormView.swift`, add a property and forward it:

```swift
struct TransactionFormView: View {
    @Bindable var viewModel: EditAddTransactionViewModel
    var focusTrigger: Int = 0
```

and at the `CurrencyAmountField(...)` call (lines 10-16) add `focusTrigger: focusTrigger` to the arguments.

- [ ] **Step 2: Add coordination state to `EditAddTransactionView`**

In `EditAddTransactionView.swift`, add alongside the existing `@State` (after line 25):

```swift
    @State private var refocusToken = 0
    @State private var savedCount = 0
    @State private var showSavedToast = false
    @State private var toastTask: Task<Void, Never>?
```

- [ ] **Step 3: Pass the token into the form**

Change the `TransactionFormView(viewModel: viewModel)` call (line 35) to:

```swift
            TransactionFormView(viewModel: viewModel, focusTrigger: refocusToken)
```

- [ ] **Step 4: Rewrite the new-transaction save branch**

Replace the `guard let existing = viewModel.editingItem else { … }` block in `saveTransaction()` (lines 73-84) with:

```swift
        guard let existing = viewModel.editingItem else {
            Task {
                do {
                    if viewModel.isRecurring {
                        try await viewModel.saveRecurringTransaction()
                    } else {
                        // Guard nil (don't `else if`): a nil input must not fall through
                        // to the success path and show a false "saved". isFormValid gates
                        // the button, so this is defensive but explicit.
                        guard let input = viewModel.buildInput() else { return }
                        try await viewModel.repo.add(input)
                    }
                    dataChanged.bump()
                    if viewModel.addAnother {
                        viewModel.resetForm()
                        savedCount += 1     // fires .sensoryFeedback(.success)
                        refocusToken += 1   // clears + re-focuses Amount (Task 2)
                        flashSavedToast()
                    } else {
                        dismiss()
                    }
                } catch {
                    // Keep the filled form; surface the existing error alert. No toast/haptic.
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showingErrorAlert = true
                }
            }
            return
        }
```

Leave the edit path (from `guard let input = viewModel.buildInput()` at line 85 onward) unchanged.

- [ ] **Step 5: Add the toast helper**

Add a method to `EditAddTransactionView` (mirrors `MainTabView`'s privacy-toast pattern at `MainTabView.swift:160-166`):

```swift
    private func flashSavedToast() {
        toastTask?.cancel()
        showSavedToast = true
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { showSavedToast = false }
        }
    }
```

- [ ] **Step 6: Add the haptic and the toast overlay**

On the top-level `VStack` in `body` (lines 34-70), add the haptic trigger and a toast overlay (owned by this view so it renders above the sheet chrome — a `MainTabView`-owned toast would be hidden behind the sheet):

```swift
        .sensoryFeedback(.success, trigger: savedCount)
        .overlay(alignment: .top) {
            if showSavedToast {
                ToastBanner(icon: "checkmark.circle.fill", message: String(localized: "Transaction saved")) {
                    EmptyView()
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showSavedToast)
```

- [ ] **Step 7: Build and run the full test suite**

`mcp__xcode__BuildProject(tabIdentifier: "windowtab1")`, then `mcp__xcode__RunSomeTests` for `EditAddTransactionViewModelTests`. Expected: build succeeds, all tests pass. Add `"Transaction saved"` to the string catalog.

- [ ] **Step 8: Manual verification (device/simulator)**

The display-text clear is view-layer and not covered by unit tests — verify by hand. With the toggle **on**, on save:
- **The Amount field visually shows empty/placeholder, not the prior number.** (This is the exact failure the Task 2 focus-cycle prevents.)
- Toast + haptic fire; type/category/note blank; the keypad returns.
- Toast renders above the sheet chrome and does not stack on rapid successive saves.
- A forced save failure keeps the filled form and shows the error alert, with no toast/haptic.
- With the toggle **off** — behavior unchanged (sheet dismisses).

- [ ] **Step 9: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/EditAddTransactionView.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/EditAddTransactionView/Components/TransactionFormView.swift PersonalFinanceTraker/PersonalFinanceTraker/Localizable.xcstrings
git commit -m "feat: keep Add sheet open on save when 'Add another' is on"
```

---

## Self-Review

**Spec coverage:** session-only/Add-mode (Global Constraints + Tasks 1/3), fully-blank reset incl. currency (Task 1 reuses `resetForm`), reset-in-place vs dismiss (Task 4 Step 4), haptic + toast (Task 4 Steps 5-6), re-focus + the display-text clear bug (Task 2), scoped error handling / no false-success (Task 4 Step 4 do/catch + nil guard), toast-above-sheet + no-stacking (Task 4 Steps 5-6). All covered.

**Placeholder scan:** none — every code step carries concrete code.

**Type consistency:** `focusTrigger: Int` is consistent across `CurrencyAmountField` (Task 2), `TransactionFormView` (Task 4 Step 1), and the `EditAddTransactionView` `@State refocusToken` (Task 4 Steps 2-3). `addAnother: Bool` consistent across Tasks 1/3/4. `savedCount`/`showSavedToast`/`toastTask` all defined in Task 4 Step 2 before use.
