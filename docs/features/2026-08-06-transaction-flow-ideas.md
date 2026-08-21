# Transaction flow ideas — backlog

Status: **parked**. To be brainstormed together in a future session (not yet specced).
Captured: 2026-08-06.

Three independent features, each its own spec → plan → build cycle.

## 1. Notification tap → Add Transaction sheet
Tapping the daily "Log today's spending" reminder should open the Add Transaction
sheet directly (after the existing PIN/biometric auth gate), saving a tap.

- Today `ReminderService` schedules the reminders but nothing handles the tap —
  it just opens the app wherever it left off. No `UNUserNotificationCenterDelegate`.
- Add sheet is `MainTabView.showingAddItemView` (`@State Bool`, `.sheet(isPresented:)`).
- `MainTabView` only exists once `authService.isUnlocked`, so auth is respected for free.
- Sketch: delegate sets a durable UserDefaults flag on tap → `MainTabView` consumes it
  in its existing `.task` (cold launch) and `scenePhase == .active` (warm) hooks.

## 2. "Add another transaction" toggle
A switch in the Add sheet that, when on, reopens a fresh sheet after saving so the
user can log several in a row. Stays on until turned off.

- Decision so far: next sheet resets **fully blank** (type + category + amount + note).
- ✅ shipped (2026-08-08, `c8948d2`) — but not as a toggle in the end. It moved
  through a pinned bottom zone (`5c4493c`) and landed (PR #35, `6b8612a`) as an
  icon-only button in the keyboard accessory bar, alongside Repeat and a math
  toggle, to stay clear of the keyboard's own accessory bar. That cost visible
  labels for first-time users — tracked as issue #31 and fixed 2026-08-20 with
  TipKit tips rather than reverting the icons. Full history in
  `docs/superpowers/plans/2026-08-08-add-another-transaction-toggle.md`.

## 3. Multi-select + bulk edit in transaction list
Select multiple transactions in the Activity list and act on them together.

- Bulk actions wanted: **delete, change category, change amount, edit description**.
- List lives in the Activity tab (`TransactionListView` / `TransactionListViewModel`).

## Backlog / follow-ups

- **Compact category presentation in the Add sheet** — ✅ done (2026-08-10, in the "Add another"
  branch). `CategoryChipsGrid`/`GoalChipsGrid` are now single-row horizontal scrollers with
  fixed-width chips instead of a multi-row grid, so a required field stays reachable above the
  keyboard. A future "recent + More…" refinement could go further but isn't needed now.
