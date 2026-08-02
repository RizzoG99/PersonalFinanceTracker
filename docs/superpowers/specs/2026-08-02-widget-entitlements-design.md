# Design: Entitlements Bootstrap + Safe-to-Spend Widget

## Problem

The app has an empty entitlements file (no App Groups, Keychain sharing, or CloudKit container), which blocks every platform-extension feature. This is the gating step for the roadmap's widget item and the upcoming iCloud sync item. This design scopes the entitlements bootstrap together with the first thing it unblocks: a home-screen widget showing "safe to spend until payday" — the app's flagship differentiator (pay-cycle-native, unlike competitors' calendar-month budgeting).

## Approach

Two Xcode targets share data through an App Group container: the existing `PersonalFinanceTraker` app target, and a new `SafeToSpendWidget` WidgetKit extension target. The app precomputes a small forward-looking snapshot and writes it into the shared container; the widget only ever reads that snapshot — it never links SwiftData, `PayCycleService`, or `SpendingForecastService` directly.

This was chosen over having the widget query SwiftData directly via a shared store, because it reuses a pattern already established in the codebase (`TransactionSnapshot`, `HealthScoreSnapshot`, `DailyForecastCacheData` — `Sendable` value types decoupled from SwiftData specifically for crossing boundaries), keeps the widget extension target small and fast, and avoids pulling the whole model/service layer into a second target that then has to stay "widget-safe" forever.

## Key decisions

- Widget headline number: **safe-to-spend until payday**, not plain balance — the differentiator, not the simplest option.
- Entitlements bootstrap scope: **App Group + CloudKit container now**, even though CloudKit sync isn't built yet — avoids a second round of Xcode target/signing changes when sync is scoped next. The CloudKit container sits unused until that feature lands.
- Data sharing: **snapshot-write pattern (Approach B)**, not direct shared-SwiftData-store access (Approach A). The widget process never touches business-logic services.
- Refresh strategy: **event-driven reload + periodic timeline backstop**. The app calls `WidgetCenter.reloadTimelines` after any transaction mutation; the snapshot itself contains several days forward (not just "today") so the periodic timeline still shows the right number on day rollover even without a fresh app-triggered write.
- Snapshot struct lives in a small shared source file added to both targets' compile membership — not a full shared framework, to avoid extra build-system overhead for one struct.
- Missing/undecodable snapshot (first install, schema mismatch after update) → widget shows a neutral empty state, never a stale or wrong number.

## Architecture notes

Where this fits in the existing codebase:

- **New:** `SafeToSpendWidget/` — new WidgetKit extension target (Xcode target creation, not just files — needs to happen in Xcode or via project file edit).
- **New:** `Utilities/SafeToSpendSnapshotWriter.swift` (app target) — builds `SafeToSpendSnapshot` from `PayCycleService` + `SpendingForecastService` + recurring commitments (once that feature lands), writes JSON to the App Group container, triggers `WidgetCenter.shared.reloadTimelines`.
- **New:** `SafeToSpendSnapshot` struct (shared file, both targets) — `Sendable`, `Codable`, today's value + N days forward.
- **New:** `SafeToSpendWidget/Provider.swift` — `TimelineProvider` reading the shared JSON and mapping to timeline entries.
- **New:** `SafeToSpendWidget/SafeToSpendWidgetView.swift` — renders the number + pay-cycle-remaining context line.
- **Modify:** `PersonalFinanceTraker.entitlements` — add App Group capability + CloudKit container entry.
- **Modify:** repository layer / view models that mutate transactions — call `SafeToSpendSnapshotWriter.write()` after mutations that affect the forecast.
- **No SwiftData schema change** — this feature adds no new persisted models; the snapshot is a transient JSON file in the App Group container, not a SwiftData entity.

## Where to start

Add the App Group entitlement to the existing app target and create the new WidgetKit extension target in Xcode first — this is the one step that can't be done by editing Swift files alone, and everything else (snapshot writer, provider, view) is inert until the target and shared container exist.
