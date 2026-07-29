# Now-Tier Quick Wins — Design

Date: 2026-07-23
Source: `docs/product-analysis-2026-07-23.md` (roadmap "Now" tier)
Scope: six small, independent items shipped as one batch on one branch.

## 1. App Intent quick-add (background save)

- New `AddTransactionIntent` using the AppIntents framework.
- Parameters: **amount** (required; AppIntents exposes it as `Double`, converted to `Decimal` at the boundary), **category** (dynamic `AppEntity` backed by existing `CategoryModel` list), **type** (default `.expense`), **note** (optional). Date is always "now".
- Saves directly via `TransactionActor` — no UI opens. Sign convention applied as everywhere else: expenses stored negative.
- `AppShortcutsProvider` entry so the intent surfaces in Spotlight/Siri/Shortcuts with zero user setup.
- Intent delegates to a small plain function so save logic is testable against `MockTransactionRepository`.
- No entitlements/App Group changes needed: the intent runs in-process (no widget/extension in this batch).

## 2. Daily logging reminder

- New `ReminderService` in `Utilities/`, wrapping `UNUserNotificationCenter`.
- Schedules a `UNCalendarNotificationTrigger` at a user-set time. **Default 21:00, off by default.** Notification permission is requested only when the user turns the toggle on.
- Profile gains a "Reminder" row: toggle + time picker. Settings stored in `AppSettings` (UserDefaults), consistent with `payCycleStartDay`.
- Skip-if-logged: on every transaction save and on app foreground, if any transaction exists dated today, cancel today's pending notification and schedule starting tomorrow.
- Clock/date injected into the scheduling decision so it is unit-testable.

## 3. Import mapping memory

- File signature = SHA-256 of the normalized header row plus delimiter.
- On completing a CSV/XLSX import, persist the column mapping and the category mappings keyed by signature.
- Storage: `ImportProfileStore`, a UserDefaults-backed Codable store — **not** SwiftData. Rationale: import profiles deliberately survive "Delete All Data" (`DataWipeService` wipes the model container only), and the import wizard stays decoupled from the model container.
  - `ponytail:` simplest store; move to SwiftData if profiles ever need syncing.
- Behavior on next import: if the signature matches a stored profile, **prefill** both wizard steps (column mapping and category mapping). The user still sees and confirms each step — one tap through. No silent auto-import.

## 4. Dashboard anomaly callout

- Dismissible card on the Dashboard, positioned between the balance card and recent transactions.
- Shows the single top anomaly from the existing `TimelineAnomalyService` for the current pay cycle (e.g. "Groceries 40% above normal this cycle").
- Dismissal stored in UserDefaults as anomaly key + pay-cycle identifier: dismissed for the rest of that cycle, reappears next cycle if still anomalous.
- No new computation — `DashboardViewModel` calls the existing service.

## 5. Delete CreditScoreCard

- Remove the `CreditScoreCard` view and its usage in the Credit tab. It renders a score with no real data source; `CreditUtilizationCard` remains and already covers the real signal.

## 6. README refresh

- Move biometric auth and full-text search out of "Work in Progress" into Features (both shipped).
- WIP list becomes: iCloud sync, budgeting, recurring transactions, widgets — matching the roadmap.

## Testing

Swift Testing (`@Test` / `#expect`) throughout, no UI tests:

- Intent save logic against `MockTransactionRepository` (sign convention, category resolution, defaults).
- `ReminderService` scheduling decisions with injected clock (skip-if-logged, reschedule-from-tomorrow).
- `ImportProfileStore` round-trip, signature computation, and match/prefill behavior.
- Anomaly-callout selection and dismissal logic in `DashboardViewModel` tests.

## Sequencing

All items independent; one branch, cheapest first:

1. README refresh
2. Delete CreditScoreCard
3. Dashboard anomaly callout
4. Import mapping memory
5. Daily logging reminder
6. App Intent quick-add

## Out of scope

Widgets, Live Activities, natural-language parsing in the intent, payday-aware reminder logic, per-bank named profiles UI (profiles are invisible; they just make re-imports faster).
