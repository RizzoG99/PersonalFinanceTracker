# Feature: Financial Pulse

## Problem
Manual finance tracking is easy to defer, and a transaction-only streak punishes users on genuine no-spend days instead of building the more valuable habit of daily awareness.

## Approach
Add a calm, abstract Financial Pulse that makes a daily money check-in visible on the Dashboard and Widget. Each day, the user can log or repeat a transaction, or explicitly choose "Nothing to log today"; either path completes a separate daily check-in without creating a fake transaction. The UI offers at most one relevant next action, and the visual moves between incomplete, settled, and attention-needed states.

Start with a rules-based v1 derived entirely from local transaction history and persisted check-ins. Build recurring-payment suggestions, unusual-spend prompts, and a weekly "one win, one action" reflection only after enough history exists and the basic check-in loop is trusted.

## Key decisions
- Use a check-in streak separate from the existing transaction streak. Transaction counts and transaction streaks remain factual.
- "Nothing to log today" is a first-class, reversible daily check-in state stored separately from `TransactionModel`.
- Use a branded abstract visual (pulse/ledger mark), not a character. Its state communicates readiness rather than guilt.
- The Widget defaults to privacy: it shows the Pulse state and action label, not balances, amounts, or category detail on the locked device.
- A user completes the check-in in the app. Widget actions may continue to open the app for "Add" or queue a repeat template, but should not silently mark a day complete.
- Show no more than one prompt at a time. Priority: unresolved check-in, then likely repeat, then later anomaly or recurring-payment prompts.
- Do not notify merely because a check-in is missing. Keep reminders opt-in and use existing suppression after the day is completed.
- All new visible strings, accessibility labels, and widget labels must be added to `Localizable.xcstrings`.

## Architecture notes
- Create `Utilities/DailyCheckInService.swift` with pure value types and rules for today's state, streak calculation, and a date-keyed completion record. Keep persistence behind a small `DailyCheckInStore` using `UserDefaults`; no SwiftData schema migration is needed for v1.
- Extend `Utilities/HabitLoggingService.swift` only where it needs to combine transaction status with check-in status for a single dashboard/widget presentation model. Do not treat a no-spend check-in as a transaction.
- Extend `Utilities/HabitWidgetSnapshotStore.swift` so the App Group snapshot carries a privacy-safe Pulse state and enough information for the widget to render it. Keep widget-side DTOs aligned with this snapshot.
- Update `Features/Dashboard/DashboardViewModel.swift` to compute the Pulse state during metric refresh, save the shared snapshot, and expose `completeNoSpendCheckIn()` plus an undo path for the current day.
- Update `Features/Dashboard/DashboardView.swift` and `Features/Dashboard/Components/DailyLoggingHabitCard.swift` to present one primary next action, the abstract Pulse visual, and a completion/undo state. Preserve the existing quick-repeat flow.
- Update `PersonalFinanceTrakerWidget/DailyLoggingHabitWidget.swift` to render the Pulse state in small, medium, and accessory families without revealing amounts. Route the check-in action into the app instead of completing it from the Widget extension.
- Update `Utilities/ReminderService.swift` to suppress an opted-in reminder after either a transaction is logged or the daily check-in is completed.
- Add focused coverage beside existing tests: `PersonalFinanceTrakerTests/Utilities/DailyCheckInServiceTests.swift`, `HabitLoggingServiceTests.swift`, `ReminderSchedulerTests.swift`, and `Features/Dashboard/DashboardViewModelTests.swift`.

## Where to start
Define and test the pure daily check-in state and streak rules first, including a no-spend completion and undo for today. This makes every UI, widget, and reminder state deterministic before the visual layer is introduced.
