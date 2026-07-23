# Delete All Data — Design

## Problem

Users have no way to clear their financial data short of deleting and reinstalling the
app. We need an in-app "Delete All Data" action for a fresh start without losing PIN /
biometric setup or profile preferences.

## Scope

**Wiped:** the 6 SwiftData models that make up financial data —
`TransactionModel`, `CategoryModel`, `CreditCardModel`, `GoalModel`,
`HealthScoreSnapshot`, `DailyForecastCache`.

**Kept:** PIN (Keychain), biometric-lock setting, full name, currency, pay-cycle
preference, and the `member_since_timestamp`. This is a data wipe, not a factory
reset — the app stays configured, just empty.

## Entry point

`Features/Profile/Views/ProfileView.swift` already has a "DATA" section containing
"Import CSV". Add a new row directly below it:

```swift
Button(role: .destructive) {
    showDeleteConfirmation = true
} label: {
    Label("Delete All Data", systemImage: "trash")
}
```

## Flow

1. **Tap "Delete All Data"** → destructive `.alert`:
   - Title: "Delete All Data?"
   - Message: "This will permanently erase every transaction, category, credit
     card, and goal. This cannot be undone."
   - Actions: "Cancel" (`.cancel`), "Delete" (`.destructive`)

2. **On "Delete"**: check `PINService().isPINSet()`.
   - **PIN set** → present a new `PINConfirmationView` as a sheet. The user must
     enter their existing PIN correctly before the wipe proceeds.
   - **No PIN set** → skip straight to step 3.

3. **Execute wipe**: call `DataWipeService.wipeAllData(context:)`, which batch-deletes
   each of the 6 model types from the shared `ModelContext` and saves.

4. **Feedback**: on success, show a confirmation alert ("All data deleted") and
   dismiss back to the Settings sheet. On failure, show an alert with the
   underlying error message (mirrors the existing `transactionViewModel.importError`
   pattern already used for CSV import failures in `ProfileView`).

Dashboard, Activity, and Insights are all SwiftData `@Query`-driven, so they show
their existing empty states automatically once the wipe completes — no additional
UI work needed there.

## PIN confirmation (new, lightweight)

`PINEntryViewModel` is tightly coupled to the app-unlock flow (`BiometricAuthService`,
`authService.unlock()`) — reusing it directly for a one-off confirmation would drag in
unrelated unlock semantics. Instead:

- **New `PINConfirmationViewModel`** (`Features/Security/ViewModels/`): holds
  `pinInput`, `isShaking`, `eyesOpen`, `errorMessage`, and a completion closure
  `onConfirmed: () -> Void`. `verifyPIN()` calls `PINService().validatePIN(_:)` and
  invokes the closure on success, or shakes + clears on failure — no interaction with
  `BiometricAuthService` at all.
- **New `PINConfirmationView`** (`Features/Security/`): visually mirrors
  `PINEntryView` (same `MonkeyAnimationView` / `PINDotsView` / `PINPadView`
  components, same `.appBackground()` styling) but with the title "Confirm your PIN"
  and no biometric/"Forgot PIN" affordances — this is a confirmation step, not a lock
  screen.

## DataWipeService (new)

`Utilities/DataWipeService.swift`:

```swift
enum DataWipeService {
    static func wipeAllData(context: ModelContext) throws {
        try context.delete(model: TransactionModel.self)
        try context.delete(model: CategoryModel.self)
        try context.delete(model: CreditCardModel.self)
        try context.delete(model: GoalModel.self)
        try context.delete(model: HealthScoreSnapshot.self)
        try context.delete(model: DailyForecastCache.self)
        try context.save()
    }
}
```

Kept as a standalone enum (not a class/service with dependencies) so it's trivially
testable and reusable — this is the only piece of real logic in the feature.

## Files

- NEW `Utilities/DataWipeService.swift`
- NEW `Features/Security/PINConfirmationView.swift`
- NEW `Features/Security/ViewModels/PINConfirmationViewModel.swift`
- EDIT `Features/Profile/Views/ProfileView.swift` — add the button, alert, and sheet
  presentation wiring
- NEW `PersonalFinanceTrakerTests/DataWipeServiceTests.swift`

## Testing

`DataWipeServiceTests` (Swift Testing, `@testable import PersonalFinanceTraker`):
- Build an in-memory `ModelContainer`, seed it via `SampleData.populateModelContext`.
- Call `DataWipeService.wipeAllData(context:)`.
- Assert `FetchDescriptor` for each of the 6 model types returns an empty array.
- Assert no error is thrown when called again on an already-empty context (idempotent).

No UI tests — the alert/sheet flow is straightforward SwiftUI wiring; a manual
simulator pass (delete with PIN set, delete with no PIN, cancel at each step) is the
verification for that part.
