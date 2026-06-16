# Feature: Goal Pockets Rework

## Problem
Goals are currently funded by manually typing "Saved so far" — no connection to real transactions. They also sit at the bottom of the Compass screen, making them easy to miss.

## Approach
Make goals into **pockets** funded by first-class transfer transactions. Add a `.transfer` case to `TransactionType`; each transfer transaction carries an optional `goalId` pointing to the destination pocket. Goal progress is computed from the sum of all transfers linked to it — the manual `currentAmount` field goes away. Goals move to the **top** of the Compass screen so they're the first thing visible.

Alternatives considered:
- Standalone `GoalDeposit` model (rejected: money would need to be recorded twice — once in transactions, once as a deposit — keeping the disconnected feeling)
- Dedicated Goals tab (rejected: too heavy for what is a savings tracker; solves the visibility problem with more scope than needed)

## Key decisions
- `.transfer` is a new case in `TransactionType`, displayed distinctly in the transaction list (e.g. "→ Pocket name" label)
- `TransactionModel` gains an optional `goalId: UUID?` — only set when type is `.transfer`
- `GoalModel.currentAmount` becomes a computed value in the ViewModel (sum of transfers), not a stored SwiftData property — remove the stored field to avoid stale data
- The "Saved so far" row is removed from `AddGoalSheet`
- Section order in `CompassView`: Goals first, then Health Score, Timeline, Category Trends, Patterns, Forecast
- Customizable section order deferred to a future enhancement

## Architecture notes

**Files to create:**
- None — rework of existing files only

**Files to modify:**
- `Models/TransactionType.swift` — add `.transfer` case with color/label
- `Models/TransactionModel.swift` — add `var goalId: UUID?` (SwiftData schema migration required)
- `Models/GoalModel.swift` — remove `currentAmount` stored property; add a convenience method or leave computation to ViewModel
- `Features/Insights/InsightsViewModel.swift` — compute `currentAmount` per goal by filtering `transactions` where `type == .transfer && goalId == goal.id`, summing amounts
- `Features/Insights/InsightsView.swift` (`CompassView`) — move `goalsSection` to be the first section in `LazyVStack`
- `Features/Insights/Components/AddGoalSheet.swift` — remove "Saved so far" `TextField` and `currentAmountText` state
- `Features/Insights/Components/GoalCard.swift` — no change needed if progress is still passed as a `Double`
- `Features/EditAddTransactionView/EditAddTransactionView.swift` — when type is `.transfer`, show a goal picker (dropdown or sheet) to select the destination pocket; `goalId` is required for transfers

**SwiftData schema changes:**
- `TransactionModel`: add `var goalId: UUID?` — lightweight migration, existing rows default to `nil`
- `GoalModel`: remove `var currentAmount: Decimal` — breaking migration, needs a migration plan or version bump

## Where to start
Add `.transfer` to `TransactionType` and add `goalId: UUID?` to `TransactionModel` — this is the schema foundation everything else depends on. Tackle the `GoalModel` stored-property removal second, since it requires a migration strategy.
