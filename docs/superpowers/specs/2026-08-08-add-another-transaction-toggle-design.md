# "Add another transaction" toggle — design

**Status:** approved, ready for implementation plan.
**Date:** 2026-08-08.

## Problem

Logging several transactions in a row means tapping "+" → fill → save → sheet
dismisses → tap "+" again, once per transaction. The reopen tap is pure friction
for anyone entering a batch (e.g. reconciling a day of receipts).

## Goal

A toggle in the Add-transaction sheet that keeps the sheet open after a save so
the user can log several in a row, each starting from a blank form.

## Product decisions (settled during brainstorming)

- **Session-only:** the toggle defaults **OFF** every time the Add sheet opens.
  No persistence across launches. "Stays on until turned off" means only across
  the sequential adds within one sitting.
- **Add-mode only:** never shown when editing an existing transaction.
- **Fully-blank reset:** the next form clears type + category + amount + note +
  recurrence. Currency is also reset — `resetForm()` restores it to the app base
  currency (`EditAddTransactionViewModel.swift:193`), which is the intended blank
  state, not an omission.
- **Feedback:** success haptic + a brief "Transaction saved" toast, because the
  sheet no longer dismisses to signal the save.
- **Re-focus Amount:** after each save the Amount field re-focuses so the user
  can type the next amount immediately.

## Core mechanic — reset in place, don't dismiss

The view model already has `resetForm()` (built for the quick-add App Intent,
`EditAddTransactionViewModel.swift:189`). On a save with the toggle on, call
`resetForm()` **instead of** `dismiss()`. No dismiss/re-present cycle — the sheet
just blanks and stays. This means zero coordination with `MainTabView` (which
owns the `.sheet(isPresented:)`) and no dismiss/re-present flicker.

Because a fresh `EditAddTransactionViewModel` is constructed each time the sheet
is presented (`MainTabView.swift`, `@State private var viewModel`), the
session-only, defaults-OFF behavior is automatic — no persistence code.

## Components / changes (4 files)

### 1. `EditAddTransactionViewModel`

- Add `var addAnother: Bool = false`.
- `resetForm()` deliberately does **not** touch `addAnother` — it is a control
  flag, not a form field, so it survives across the sequential saves.

### 2. `TransactionFormView`

- Add `Toggle("Add another", isOn: $viewModel.addAnother)`, gated on
  `viewModel.editingItem == nil`, styled like and placed near the existing
  "Repeat" (`isRecurring`) section (`TransactionFormView.swift:51-71`).
- Label wrapped in `String(localized: "Add another")` and added to the string
  catalog.

### 3. `CurrencyAmountField`

**Why this exists — clearing the stale display, not raising the keyboard.**
The field renders a private `@State displayText`, not `amount` directly.
`displayText` only re-syncs from `amount` in three places
(`CurrencyAmountField.swift:75-113`): `onAppear`, `onChange(of: amount)` (guarded
by `if !isFocused`), and `onChange(of: isFocused)`. In the add-another happy path
the keyboard never dismisses, so `isFocused` stays `true` the whole time:
`resetForm()` sets `amount = 0`, but the `onChange(of: amount)` handler bails on
its `!isFocused` guard and focus never changes — so `displayText` keeps the
previously typed number (e.g. `42,00`) while the model is `0`. The form looks
un-blanked. Re-focusing is *mostly already true* (the field never lost focus);
the token's real job is to force `displayText` back to empty.

- Add an optional `focusTrigger` input (an `Int` token; default such that
  existing callers are unaffected).
- On `.onChange(of: focusTrigger)`, force a **focus cycle**: set
  `isFocused = false`, then the existing async hop
  `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }`
  (`CurrencyAmountField.swift:101-108`). The `false → true` transition fires
  `onChange(of: isFocused)`, whose logic — with `amount == 0` after the reset —
  sets `displayText = ""` on both branches, clearing the field and re-presenting
  the keypad. The async hop is load-bearing: a bare synchronous set does not
  reliably re-present the keyboard.
- **No `!isFocused` guard.** The guard would make the token bump a no-op while the
  field is focused — which it always is here — defeating the clear. The bump only
  ever happens on save, never mid-edit, so there is no formatter-thrash risk to
  guard against.
- The field keeps owning its `@FocusState`; the parent only bumps the token.

### 4. `EditAddTransactionView` — coordination point

State:
- `@State private var refocusToken = 0`
- `@State private var savedCount = 0`  (drives the haptic)
- `@State private var showSavedToast = false`
- `@State private var toastTask: Task<Void, Never>?`

Save flow — in `saveTransaction()`'s **new-transaction** branch
(`EditAddTransactionView.swift:72-84`), replace the unconditional
`try? await repo.add` + `dismiss()` with:

```
do {
    if viewModel.isRecurring {
        try await viewModel.saveRecurringTransaction()
    } else {
        // Guard nil, don't `else if`: a nil input must NOT fall through to
        // dataChanged.bump() + the success toast/haptic as if it saved.
        // isFormValid gates the save button so this is defensive, but explicit.
        guard let input = viewModel.buildInput() else { return }
        try await viewModel.repo.add(input)
    }
    dataChanged.bump()
    if viewModel.addAnother {
        viewModel.resetForm()
        savedCount += 1        // fires .sensoryFeedback(.success)
        refocusToken += 1      // re-focus Amount
        flashSavedToast()      // show toast, auto-hide ~1.5s
    } else {
        dismiss()
    }
} catch {
    viewModel.errorMessage = error.localizedDescription
    viewModel.showingErrorAlert = true   // keep the filled form; no toast/haptic
}
```

- **Error handling (scoped):** the add-another branch converts the pre-existing
  silent `try?` into a real `do/catch` so a failed save keeps the filled form and
  raises the view model's existing error alert (`showingErrorAlert` /
  `errorMessage`) instead of showing false "saved" feedback. This fix is scoped
  to the add-another path only — the edit path and any other `try?` sites are
  left as-is; a broader save-path error-handling overhaul is out of scope.
- **Haptic:** `.sensoryFeedback(.success, trigger: savedCount)` on the view —
  native SwiftUI, no `UINotificationFeedbackGenerator` boilerplate. iOS 17+,
  which the app's deployment target already exceeds.
- **Toast:** a `ToastBanner` (`DesignTokens.swift:179`) overlay lives **inside**
  `EditAddTransactionView`, because the sheet covers `MainTabView` and a toast
  owned by `MainTabView` would not show through. Message
  `String(localized: "Transaction saved")`. `flashSavedToast()` cancels any prior
  `toastTask`, sets `showSavedToast = true`, sleeps ~1.5s, then clears it — the
  same pattern `MainTabView` uses for the privacy toast
  (`MainTabView.swift:160-166`), so rapid successive saves don't stack toasts.

## Interactions & edge cases

- **Recurring + add-another:** `resetForm()` clears `isRecurring` too, so the next
  entry is fully blank. Correct.
- **Validation after reset:** `isFormValid` is false immediately after
  `resetForm()` (amount 0, no category), so the save button is disabled until the
  next entry is filled — no accidental empty re-save.
- **Save in flight:** `buildInput()` result is captured inside the save `Task`
  before any reset runs; `resetForm()` executes only after `await` completes, so
  there is no race with the in-flight `repo.add`.

## Testing

- Unit: `resetForm()` clears all form fields but preserves `addAnother`.
- Unit: `isFormValid` is false immediately after `resetForm()`.
- Manual run (device/simulator) — the display-text clear is view-layer and is
  NOT covered by the unit tests above, so verify it explicitly. With the toggle
  on, on save:
  - **The Amount field visually shows empty/placeholder, not the prior number**
    (this is the bug the focus-cycle fix in §3 exists to prevent — the model
    resets to 0 but `displayText` would otherwise keep the typed value).
  - Toast + haptic fire; the rest of the form (type/category/note) blanks; the
    keypad returns.
  - Toast renders above the sheet chrome and does not stack on rapid successive
    saves.
  - A forced save failure keeps the filled form and shows the error alert, with
    **no** toast/haptic.
  - With the toggle off — behavior is unchanged (sheet dismisses).
