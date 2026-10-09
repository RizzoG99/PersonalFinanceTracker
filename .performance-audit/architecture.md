# Performance Audit Architecture

## Snapshot and scope

This audit targets the native iOS app and its two WidgetKit extensions in the current checkout at commit `b91ee335d57e535fa736f011bf348188607d178c`. The checkout contains pre-existing uncommitted changes, so conclusions describe this filesystem snapshot rather than a clean commit. No production code will be modified.

Before publication, a focused delta review covered the performance-sensitive changes through `dcbb22ded9a08fb4272c352635ce5796d7d5e825` (PR #217). It is recorded in `validation/pr217-delta-review.md`; unaffected architecture remains the original snapshot.

The app is a SwiftUI application with SwiftData persistence. It targets iPhone and iPad on iOS 26 and uses Swift concurrency. The main target contains 229 Swift files; the wider app, test, shared, and extension surfaces contain 311 Swift files. The largest feature areas are Insights (36 Swift files) and TransactionListView (26), followed by Profile, Security, Dashboard, iPad, FeatureDiscovery, CategorySettings, EditAddTransactionView, Credit, Plan, Budgets, and the main tab shell.

## Targets and dependencies

- `PersonalFinanceTraker`: main SwiftUI app.
- `PersonalFinanceTrakerWidget`: WidgetKit extension for logging and receipt entry.
- `SafeToSpendWidgetExtension`: WidgetKit extension backed by an app-group snapshot.
- `PersonalFinanceTrakerTests`: Swift Testing unit and integration coverage.
- `PersonalFinanceTrakerUITests`: UI, launch, and screenshot coverage.
- Swift packages: CoreXLSX and ZIPFoundation, used by spreadsheet and archive workflows.
- Relevant Apple frameworks include SwiftUI, SwiftData, Charts, Vision, Core Image, AVFoundation, TipKit, WidgetKit, UserNotifications, LocalAuthentication, and CryptoKit.

There is one remote runtime content path in `FeatureDiscoveryService` via `URLSession`. Core financial data is otherwise local-first. Disk-heavy paths include SwiftData, CSV/XLSX import/export, encrypted backup/restore, feature-discovery assets, receipt image handling, and app-group widget snapshots.

## Composition and state flow

`PersonalFinanceTrakerApp` synchronously obtains `AppContainer.shared`, applies global appearance, configures notification and TipKit behavior, and hosts `AuthenticationWrapper`. `AppContainer` creates the SwiftData `ModelContainer`, checks/seeds default categories, and applies file-protection attributes to the SQLite store and sidecars.

After authentication, `AppShellModels` creates a single `TransactionActor` repository plus long-lived transaction-list, dashboard, and insights/compass view models. A `DataChangedSignal` coordinates refreshes across feature boundaries. The shell chooses iPhone tab navigation or the iPad root layout.

`TransactionActor` is the persistence boundary. It serializes SwiftData access and maps models into sendable snapshots. Many mutations also rebuild the Safe-to-Spend app-group snapshot by fetching transactions and active recurrence rules. Feature view models derive list rows, groupings, summaries, forecasts, recurrence suggestions, chart data, and import previews from those snapshots.

## Performance-sensitive user journeys

1. Cold launch: model-container creation, store opening, category count/seed, file protection, TipKit configuration, splash/authentication, and shell model construction.
2. Activity: fetch all transactions/travels/categories, search and filter, group by date/travel, render large sections, perform bulk edits, and refresh after data changes.
3. Dashboard and Insights: repeatedly derive totals, budgets, forecasts, health scores, trends, category breakdowns, and Charts data from transaction snapshots.
4. Add/edit transaction: category loading, form-derived state, save, recurrence work, cross-feature refresh, and Safe-to-Spend widget refresh.
5. Receipt scan: camera frame delivery, rectangle detection, capture/crop, image normalization/downscaling, two-pass Vision recognition, parsing, and category inference.
6. Import/export/backup: read and parse CSV/XLSX, map and deduplicate rows, batch persistence, serialize snapshots, encrypt/archive, and write files.
7. Recurrence and planning: detect patterns, materialize occurrences, compute future charges and forecasts, and refresh caches.
8. Widgets: load small app-group snapshots and route deep links back into the app.

## Existing mitigation and caching

- SwiftData access is isolated behind `TransactionActor` and returns snapshots rather than live models.
- Transaction filtering and grouping already use cancellable tasks and detached work in selected paths.
- Receipt images are downscaled before Vision; a shared `CIContext` avoids repeated context construction.
- At the original snapshot, a daily forecast cache reduced repeated forecast work; PR #217 later removed that forecast and cache. Feature-discovery local/remote content still reduces repeated network work.
- Import result rendering caps visible preview rows.
- View models are constructed once in `AppShellModels` and survive shell lock/unlock cycles.

These are architecture facts, not proof that the protected paths are fast enough.

## Tests, benchmarks, and profiling availability

The repository has broad unit coverage for transaction lists, dashboard, insights, imports, recurrence, backup, receipt parsing, widgets, and services. UI tests include direct launch timing logic and screenshot flows. No dedicated XCTest performance suite, MetricKit pipeline, signposts, or checked-in benchmark harness was found during reconnaissance.

Available validation tools include `scripts/xcb build`, `scripts/xcb test`, UI tests, Xcode Instruments (Time Profiler, SwiftUI, Allocations/Leaks, Core Data/SwiftData, File Activity, Network, and Energy), MetricKit for field telemetry if intentionally added later, and deterministic large-data fixtures that can be built from `SampleData` patterns. Existing scripts will not be executed during static screening without a validation need.

## Exclusions

- `.git/`, `.build/`, `graphify-out/`, derived data, simulator data, generated archives, screenshots, and exported assets.
- App-icon source projects and static asset catalogs except where image size or loading is directly implicated.
- Documentation and historical plans except when needed to understand intended behavior.
- Third-party package source; only call-site behavior is in scope.
- Test code as an optimization target. Tests are inspected only for coverage, realistic data sizes, and validation opportunities.
- Pre-existing user modifications are not edited or reverted.

## Reconnaissance limitations

This phase is static. It provides no device measurements, frame-rate traces, memory graphs, launch metrics, query plans, or energy measurements. The local graph index was low-recall for cross-cutting runtime questions, so targeted symbol searches were used to establish the architecture. Any runtime-impact claim remains unconfirmed until reproduced or measured.
