# Feature: Goals Section Redesign

## Problem
The Goals section has three gaps: `colorToken` is stored on `GoalModel` but never used (all cards render in indigo), there is no way to add funds to a goal without manually creating a Transfer transaction, and there is no visual payoff when a goal reaches 100%.

## Approach
Keep the existing 2-column `GoalCard` grid clean — card shows only color-accented icon, name, progress bar, and percentage. Tapping a card opens a new `GoalDetailSheet` that owns: a full progress ring with the goal's color, a prominent "Add Funds" button that internally creates a Transfer transaction tagged with the goal's `id`, and a celebration state (animation + "Goal reached!" message) when `currentAmount >= targetAmount`. Editing moves to a pencil button inside the detail sheet, removing the direct edit tap from the card.

## Key decisions
- `colorToken` is already on `GoalModel` and stored — just needs to be surfaced in the UI (color picker in `AddGoalSheet`, color used in `GoalCard` and `GoalDetailSheet`)
- "Add Funds" creates a `TransactionModel` with `goalId` set and a positive amount (Transfer type), matching the existing `transferTotal(for:)` mechanism — no schema change needed
- Celebration state lives inside `GoalDetailSheet`, not the card — the card is too small for a meaningful animation
- The existing edit flow (`goalToEdit` binding → `AddGoalSheet`) is preserved; the detail sheet just adds a pencil toolbar button that sets `goalToEdit`
- Color tokens should reuse the existing `CategoryModel` color token set (already defined in the app) to stay consistent

## Architecture notes

**Files to create:**
- `Features/Insights/Components/GoalDetailSheet.swift` — progress ring, Add Funds button, celebration state, edit entry point

**Files to modify:**
- `Features/Insights/Components/GoalCard.swift` — use `colorToken` for icon and progress bar color; remove `onTap` edit behavior, replace with navigation to detail sheet
- `Features/Insights/Components/GoalsSection.swift` — add `@State var selectedGoal: GoalModel?` and a `.sheet(item:)` presenting `GoalDetailSheet`; pass `onFund` and `onEdit` callbacks
- `Features/Insights/Components/AddGoalSheet.swift` — add a color picker row (reuse existing color token palette)
- `Features/Insights/InsightsViewModel.swift` — add `func addFunds(amount: Decimal, to goal: GoalModel)` that creates and persists a Transfer `TransactionModel` with `goalId`

**SwiftData schema changes:** None — `GoalModel.colorToken` and `TransactionModel.goalId` already exist.

## Where to start
Create `GoalDetailSheet.swift` with the progress ring, color accent, and "Add Funds" entry point — wire it up in `GoalsSection` first, then layer in the celebration state and color picker afterward.
