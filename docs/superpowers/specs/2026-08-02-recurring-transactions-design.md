# Feature: Recurring Transactions

## Problem
Rent, salary, and subscriptions make up most of a real ledger, but today every occurrence must be re-entered by hand — the top-cited abandonment driver for manual trackers. Recurring transactions remove that friction and unlock downstream features (bill reminders, subscription insights, forecasts using known future cash flows instead of pure extrapolation).

## Approaches considered

**A. Separate `RecurrenceRule` model + launch/foreground materialization (chosen).** A new SwiftData model holds the recurrence template; a service materializes due occurrences into real `TransactionModel` rows when the app becomes active. Clean split-on-edit history, no background execution.

**B. Recurrence fields directly on `TransactionModel` as a "template" row.** Simpler schema (no new model), but can't cleanly support "this and future" edits without sentinel/marker rows, and conflates "real transaction" with "template" in one table.

**C. Background-task-driven materialization (`BGTaskScheduler`).** More timely — doesn't wait for the app to be opened — but the codebase deliberately avoids background execution (see `DailyForecastCache` and `ReminderService`, both launch/foreground-triggered). Unneeded complexity for a manual tracker, not a bill-pay system.

Approach A is the only one that gets clean split-on-edit history without extra machinery, and it matches the app's existing launch/foreground-triggered pattern (`MainTabView`'s `.task {}` + `scenePhase == .active`, already used for reload-on-foreground and reminder rescheduling).

## Key decisions
- v1 frequencies: **Monthly, Weekly, Yearly**, with an `interval: Int` field so "every 2 weeks" is possible later without a schema change.
- Creation only via the existing Add/Edit Transaction sheet — no dedicated "Recurring" list screen in v1 (Budgets tab is the precedent if one is ever needed).
- Edit/delete scope: **this-and-future vs. whole series**, not per-instance overrides (EventKit-style exceptions are a later iteration if needed).
- Category is a real link to `CategoryModel` (`categoryPersistentId` + denormalized `category` name), mirroring `TransactionInput` exactly — not a bare string. Category deletion nullifies the link on the rule, same as it does on transactions today (`CategoryModel`'s relationship is `deleteRule: .nullify`).
- Goal-linked recurrence (e.g. "auto-contribute €200/mo to a goal") **is in scope for v1**: `RecurrenceRule` carries an optional `goalId`, threaded through to materialized transactions exactly like a manual goal contribution.
- Materialization inserts **every** due occurrence since `lastMaterializedDate`, however large the backlog (e.g. 6 months idle = 6 monthly rows appear at once). No cap, no silent gap-skipping — matches "never miss a real entry."
- Materialization is **silent**: new rows appear in Activity/Dashboard on next reload, no toast/banner, consistent with how the app already reloads silently on foreground for other out-of-band changes (App Intent quick-add).
- **"Delete series" never touches history.** It closes the rule (`endDate = today - 1`) and removes only future, un-materialized transactions. Past materialized transactions become ordinary standalone transactions and are never rewritten — history in a finance ledger must stay immutable.
- Materialization is launch-triggered and foreground-triggered, not a background task — matches how `DailyForecastCache` and the daily log reminder already avoid background execution.
- Past materialized transactions are always editable/deletable individually like any normal transaction — no special-casing needed there.

## Architecture

### `Models/RecurrenceRule.swift` (new)
SwiftData `@Model`, field shape mirrors `TransactionInput` (`Models/Snapshots.swift:143`) plus recurrence-specific fields:

```swift
@Model
final class RecurrenceRule {
    var frequency: RecurrenceFrequency   // enum: weekly, monthly, yearly
    var interval: Int                    // "every N <frequency>"
    var startDate: Date
    var endDate: Date?                   // nil = open-ended / active
    var lastMaterializedDate: Date?      // catch-up cursor; nil = never materialized

    // Transaction template — mirrors TransactionInput
    var amount: Decimal
    var note: String
    var category: String
    var currencyCode: String
    var goalId: UUID?

    @Relationship(deleteRule: .nullify)
    var categoryModel: CategoryModel?
}
```

### `Models/TransactionModel.swift` (modify)
Add `var recurrenceRuleId: PersistentIdentifier?` — back-link tagging a materialized row to the rule that produced it. `nil` for manually entered transactions.

### `Utilities/RecurrenceMaterializationService.swift` (new)
- `materialize(using repo: ITransactionRepository) async throws` — fetches active rules (`endDate == nil || endDate >= today`), and for each: computes occurrence dates from `lastMaterializedDate ?? startDate` up to today using `Calendar.date(byAdding:to:)` with day-clamping (so a monthly rule starting Jan 31 lands on Feb 28/29, never silently skipped or rolled forward), builds a `TransactionInput` per occurrence (tagged via the new `recurrenceRuleId`), inserts via `TransactionActor.addBatch`, and advances `lastMaterializedDate`.
- Month-end clamping is the riskiest logic in the feature — gets a dedicated unit test asserting correct occurrence generation across month-end edge cases before anything else is built.

### `Models/TransactionRepository.swift` (`ITransactionRepository`) (modify)
Add:
- `addRecurrenceRule(_ input: RecurrenceRuleInput) async throws`
- `fetchRecurrenceRules() async throws -> [RecurrenceRuleSnapshot]`
- `closeRecurrenceRule(id:endDate:) async throws` — used by both "this and future" edits and "delete series"
- `updateRecurrenceRule(id:with:) async throws` — "all occurrences" edit path
- `deleteFutureUnmaterializedOccurrences(ruleId:from:) async throws`
- `fetchOccurrences(ruleId:) async throws -> [TransactionSnapshot]`

### Add/Edit Transaction sheet + `EditAddTransactionViewModel` (modify)
- Repeat toggle + frequency/interval picker.
- Editing or deleting a transaction with a non-nil `recurrenceRuleId` prompts: "This transaction" / "This and future" / "All future occurrences" before applying the change. Deleting "this and future" closes the rule at the edit date; editing "all occurrences" mutates the rule in place, deletes future un-materialized rows, and lets the next materialization pass regenerate them under the new template.

### App launch / foreground hook (`Features/MainTabView/MainTabView.swift`) (modify)
No new hook — call `RecurrenceMaterializationService.materialize` from the existing `.task {}` block (app launch, alongside `viewModel.load()`) and from the existing `.onChange(of: scenePhase)` `.active` branch (foreground resume, alongside the existing `dashboardViewModel.reload()` / `viewModel.reload()` calls).

### `Utilities/SpendingForecastService.swift` (modify, later)
Feed known future occurrences (from active `RecurrenceRule`s, projected forward) into the forecast instead of pure historical extrapolation. Not required for v1 landing, but the model shape (rule → projectable future dates) supports it without further schema change.

### Later, not v1
- Wire into `Utilities/ReminderService.swift` for "bill due" notifications.
- Insights card for "you spend €X/mo on subscriptions."
- Per-instance exception overrides (EventKit-style).
- Dedicated "Recurring" management screen.

### SwiftData schema change
Yes — new `RecurrenceRule` model, new `recurrenceRuleId` field on `TransactionModel`. Per the no-App-Store / reinstall-OK migration policy, no migration path needed; reinstall during development.

## Where to start
Add the `RecurrenceRule` model and `RecurrenceMaterializationService` with a unit test asserting correct occurrence-date generation across month-end edge cases (e.g. a monthly rule starting Jan 31) — that date math is the riskiest part of the whole feature, and everything else (UI, forecast integration) builds on it being right.
