# Design: Entitlements Bootstrap + Safe-to-Spend Widget

## Problem

The app has an empty entitlements file (no App Groups, Keychain sharing, or CloudKit container), which blocks every platform-extension feature. This is the gating step for the roadmap's widget item and (separately, later) the iCloud sync item. This design scopes the entitlements bootstrap together with the first thing it unblocks: a home-screen widget showing "safe to spend until payday" — the app's flagship differentiator (pay-cycle-native, unlike competitors' calendar-month budgeting). CloudKit entitlements are explicitly out of scope here — they get added when sync is designed, not preemptively.

## Approach

Two Xcode targets share data through an App Group container: the existing `PersonalFinanceTraker` app target, and a new `SafeToSpendWidget` WidgetKit extension target. The app precomputes a small forward-looking snapshot and writes it into the shared container; the widget only ever reads that snapshot — it never links SwiftData, `PayCycleService`, or `SpendingForecastService` directly.

This was chosen over having the widget query SwiftData directly via a shared store, because it reuses a pattern already established in the codebase (`TransactionSnapshot`, `HealthScoreSnapshot`, `DailyForecastCacheData` — `Sendable` value types decoupled from SwiftData specifically for crossing boundaries), keeps the widget extension target small and fast, and avoids pulling the whole model/service layer into a second target that then has to stay "widget-safe" forever.

## Key decisions

- Widget headline number: **safe-to-spend until payday**, not plain balance — the differentiator, not the simplest option.
- Entitlements bootstrap scope: **App Group only**, not CloudKit. Adding a CloudKit container to an already-App-Group-enabled target later is a small, well-trodden edit — not a rebootstrap — so provisioning it now would mean signing infrastructure for a feature (sync) that isn't designed yet, with no real savings later. YAGNI; add it when sync is actually scoped.
- Data sharing: **snapshot-write pattern (Approach B)**, not direct shared-SwiftData-store access (Approach A). The widget process never touches business-logic services.
- Refresh strategy: **event-driven reload + periodic timeline backstop**. The snapshot carries **N = 7 days forward** (today + one full pay-cycle-friendly window), so the periodic timeline still shows the right number on day rollover even without a fresh app-triggered write. If the app hasn't launched in more than 7 days, the provider runs off the end of the cached array — this is treated as the same failure class as a missing snapshot: fall through to the neutral empty state, never display the last known (now-stale) number.
- Snapshot struct lives in a small shared source file added to both targets' compile membership — not a full shared framework, to avoid extra build-system overhead for one struct.
- Missing, undecodable, or **exhausted (past the last cached day)** snapshot → widget shows a neutral empty state, never a stale or wrong number.
- Snapshot writer trigger: **the transaction-mutation methods on `TransactionActor`** (`add`, `addBatch`, `update`, `delete`, plus the recurrence-rule mutators `addRecurrenceRule`/`updateRecurrenceRule`/`deleteOccurrences`/`materializeOccurrences`), not `saveForecastCache`. `materializeOccurrences` writes recurring occurrences into the store as real transactions and changes future spending, so it belongs in the trigger list; `closeRecurrenceRule` is excluded since it only sets an end date and doesn't alter any existing transaction. `saveForecastCache` has exactly one caller (`InsightsViewModel.computeForecast()`) and only fires when the Insights screen recomputes — a transaction logged from the Activity tab never touches it, which would leave the widget stale right after the moment freshness matters most (just after spending money). The mutation methods are the true choke point every transaction passes through. Since they don't currently compute a forecast, the snapshot writer calls `SpendingForecastService` itself rather than reading a cache that may not reflect the just-made change.

## Architecture notes

Where this fits in the existing codebase:

- **New:** `SafeToSpendWidget/` — new WidgetKit extension target (Xcode target creation, not just files — needs to happen in Xcode or via project file edit).
- **New:** `Utilities/SafeToSpendSnapshotWriter.swift` (app target) — builds `SafeToSpendSnapshot` from `PayCycleService` + `SpendingForecastService` + recurring commitments (once that feature lands), writes JSON to the App Group container.
- **New:** `SafeToSpendSnapshot` struct (shared file, both targets) — `Sendable`, `Codable`, today's value + 7 days forward.
- **New:** `SafeToSpendWidget/Provider.swift` — `TimelineProvider` reading the shared JSON; if the array is exhausted for the requested date, returns the neutral empty-state entry instead of the last cached value.
- **New:** `SafeToSpendWidget/SafeToSpendWidgetView.swift` — renders the number + pay-cycle-remaining context line.
- **Modify:** `PersonalFinanceTraker.entitlements` — add App Group capability only.
- **Modify:** `TransactionActor.add`, `.addBatch`, `.update`, `.delete`, `.addRecurrenceRule`, `.updateRecurrenceRule`, `.deleteOccurrences`, `.materializeOccurrences` — after the mutation commits, call `SafeToSpendSnapshotWriter.write()` (which itself invokes `SpendingForecastService` to get a current projection) and `WidgetCenter.shared.reloadTimelines`. These are the true choke points every transaction-affecting change passes through; `saveForecastCache` is not one of them, since its only caller is `InsightsViewModel.computeForecast()`.
- **No SwiftData schema change** — this feature adds no new persisted models; the snapshot is a transient JSON file in the App Group container, not a SwiftData entity.

## Where to start

Add the App Group entitlement to the existing app target and create the new WidgetKit extension target in Xcode first — this is the one step that can't be done by editing Swift files alone, and everything else (snapshot writer, provider, view) is inert until the target and shared container exist.
