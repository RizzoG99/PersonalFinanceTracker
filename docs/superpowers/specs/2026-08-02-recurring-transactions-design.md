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
- Category is a real link to `CategoryModel` via a `@Relationship`, plus a denormalized `category` name string (so the rule still reads sensibly if the category is later deleted) — not a bare string. Deletion nullifies the relationship on the rule, same as it does on transactions today (`CategoryModel`'s relationship is `deleteRule: .nullify`).
- `RecurrenceRule` carries an optional `goalId: UUID?` field for forward compatibility, but **goal-linked auto-contribution behavior is deferred past v1** — the field is threaded through to materialized transactions like any manual entry, but goal-completion edge cases (does the rule keep firing after the goal is reached? overshoot handling?) are explicitly out of scope until the core recurrence loop is proven.
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
    @Attribute(.unique) var id: UUID
    var frequency: RecurrenceFrequency   // enum: weekly, monthly, yearly
    var interval: Int                    // "every N <frequency>"
    var startDate: Date
    var endDate: Date?                   // nil = open-ended / active
    var lastMaterializedDate: Date?      // catch-up cursor; nil = never materialized

    // Transaction template — mirrors TransactionInput
    var amount: Decimal
    var note: String
    var category: String                 // denormalized name, survives category deletion
    var currencyCode: String
    var goalId: UUID?                    // field only; auto-contribution behavior deferred

    @Relationship(deleteRule: .nullify)
    var categoryModel: CategoryModel?
}
```

### `Models/TransactionModel.swift` (modify)
Add `var recurrenceRuleId: UUID?` — back-link tagging a materialized row to the rule that produced it, `nil` for manually entered transactions. **Not** `PersistentIdentifier`: it isn't stable across store rebuilds, and every back-link would break on the reinstalls this project's migration policy assumes. `UUID` is the same choice already made for `goalId`.

### `Utilities/RecurrenceMaterializationService.swift` (new)
- `materialize(using repo: ITransactionRepository) async throws` — fetches active rules (`endDate == nil || endDate >= today`), and for each: computes occurrence dates from `lastMaterializedDate ?? startDate` up to today using `Calendar.date(byAdding:to:)` with day-clamping (so a monthly rule starting Jan 31 lands on Feb 28/29, never silently skipped or rolled forward), builds a `TransactionInput` per occurrence (tagged via the new `recurrenceRuleId`), inserts via `TransactionActor.addBatch`, and advances `lastMaterializedDate` — the cursor write happens in the same pass as the insert, not after, so a second concurrent pass reading mid-flight never sees a stale cursor with a partially-inserted batch.
- **Re-entrancy guard:** cold launch fires both `.task {}` and the initial `scenePhase == .active` transition close together, and `TransactionActor` only serializes individual calls, not the read-`lastMaterializedDate`-modify-write across two separate `materialize()` passes — without a guard, two overlapping passes can both read the same cursor and double-insert. The service holds a single in-flight `Task<Void, Error>?`; a second call while one is running awaits the existing task instead of starting a new one.
- Month-end clamping is the riskiest logic in the feature — gets a dedicated unit test asserting correct occurrence generation across month-end edge cases before anything else is built.

### `Models/TransactionRepository.swift` (`ITransactionRepository`) (modify)
Add:
- `addRecurrenceRule(_ input: RecurrenceRuleInput) async throws`
- `fetchRecurrenceRules() async throws -> [RecurrenceRuleSnapshot]`
- `closeRecurrenceRule(id:endDate:) async throws` — used by both "this and future" edits and "delete series"
- `updateRecurrenceRule(id:with:) async throws` — "this and future" edit path
- `deleteFutureUnmaterializedOccurrences(ruleId:from:) async throws`

(No `fetchOccurrences` — nothing in this design reads occurrences by rule; edits/deletes work off `recurrenceRuleId` on the transaction itself. Add it later if something needs it.)

### Add/Edit Transaction sheet + `EditAddTransactionViewModel` (modify)
- Repeat toggle + frequency/interval picker.
- Editing or deleting a transaction with a non-nil `recurrenceRuleId` prompts with exactly two options: **"This transaction"** / **"This and future."** (Past materialized rows always keep the old template even when the rule is edited going forward, so there is no third "all occurrences" option that would be honest about what it does.) "This and future" on delete closes the rule at the edit date; "this and future" on edit mutates the rule in place, deletes future un-materialized rows, and lets the next materialization pass regenerate them under the new template.

### App launch / foreground hook (`Features/MainTabView/MainTabView.swift`) (modify)
No new hook — call `RecurrenceMaterializationService.materialize` from the existing `.task {}` block (app launch, alongside `viewModel.load()`) and from the existing `.onChange(of: scenePhase)` `.active` branch (foreground resume, alongside the existing `dashboardViewModel.reload()` / `viewModel.reload()` calls). The re-entrancy guard above is what makes calling it from both sites safe.

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
