# Android Room Entity and Repository Map

## Decision summary

Android v1 uses Room for durable financial records and DataStore for app and device preferences. Repositories expose domain models and suspend/`Flow` APIs; feature ViewModels never depend on Room entities or DAOs directly.

This maps the current iOS SwiftData schema without reproducing SwiftData implementation details. iOS-to-Android onboarding migration is deferred to enhancement #87 and does not shape the Android v1 primary keys.

## Schema versions

The active Room schema is **version 3**. Every version is exported to `Android/app/schemas/com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase/` and validated by `RoomMigrationTest`.

| Version | Change | Migration |
| --- | --- | --- |
| 1 | Initial eight-table schema. Categories are unique on `(name, type)`. | — |
| 2 | Adds `categories.normalizedName` and moves uniqueness to `(normalizedName, type)`, so case and surrounding whitespace can no longer create duplicates. | `MIGRATION_1_2` adds the column, backfills it through `CategoryNameValidator.normalized`, and replaces the index. The backfill runs in Kotlin rather than as `lower(trim(name))` because SQLite's `trim()` strips only U+0020 and its `lower()` is ASCII-only on Android, which would store a value the app never computes. |
| 3 | No structural change. `credit_cards` was briefly dropped from the entity set inside an unreleased development window and restored with its original columns, so `3.json` and `2.json` carry the same `identityHash`. | `MIGRATION_2_3` is deliberately empty. `RoomMigrationTest` asserts the two exported identity hashes still match, so the no-op cannot silently become wrong. |

Migrations are registered once, in `PersonalFinanceDatabase.MIGRATIONS`; `PersonalFinanceApplication` and the migration tests both read that list. Destructive fallback is never enabled — a missing or failing migration refuses to open the database and leaves the source file recoverable.

A database created fresh at version 3 during the credit-card exclusion window has no `credit_cards` table and fails Room's identity check after the restore. No such database was ever distributed; a developer who has one reinstalls.

## Database

`PersonalFinanceDatabase` contains the following Room entities:

| Android entity | Primary key | iOS source | Relationships and notes |
| --- | --- | --- | --- |
| `TransactionEntity` | generated UUID string | `TransactionModel` | Nullable `categoryId`, `goalId`, and `recurrenceRuleId`; preserve `categoryLabel` as the historical display snapshot. |
| `CategoryEntity` | UUID string | `CategoryModel` | Name, normalized name, icon token, type, colour token, optional monthly budget, and currency. The normalized name plus type is unique, so Income and Expense can both have “Other”, while case or surrounding whitespace cannot create duplicates. |
| `GoalEntity` | UUID string | `GoalModel` | Goal progress remains derived from linked transactions, not stored as a mutable balance. |
| `CreditCardEntity` | UUID string | `CreditCardModel` | Name, last four digits, balance, limit, colour token, and currency. |
| `RecurrenceRuleEntity` | UUID string | `RecurrenceRule` | Frequency, interval, active dates, materialization cursor, transaction template, and nullable category/goal IDs. |
| `HealthScoreSnapshotEntity` | generated UUID string | `HealthScoreSnapshot` | Timestamp and component scores; preserve history. |
| `DailyForecastCacheEntity` | constant singleton key | `DailyForecastCache` | A derived cache. It may be cleared and recomputed without user-data loss. |
| `MerchantCategoryMappingEntity` | normalized merchant string | `MerchantCategoryMapping` | Maps a learned merchant to a category UUID. |

Room foreign keys use `SET NULL` for category and goal references. A deleted category or goal must not delete historical transactions or recurrence rules; their display snapshot remains available. Deleting a recurrence rule does not delete already materialized transactions.

All multi-record writes, recurring-occurrence materialization, import batches, and delete-all operations run inside a Room transaction.

## Value encoding

- Money uses `BigDecimal` in the domain layer and a canonical decimal string in Room. It never uses `Double` or `Float`.
- Amount signs match iOS: expense is negative and income is positive.
- Timestamps use `Instant` in the domain layer and epoch milliseconds in Room. Calendar-sensitive logic uses the user’s current `ZoneId` and is covered by pay-cycle and daylight-saving tests.
- UUIDs are stored as strings. Android generates a UUID for every newly created transaction; this creates a stable local identity without depending on a Room row ID.
- Enums such as category type and recurrence frequency use stable lowercase string values. Android presentation labels are localized separately.
- The forecast cache stores its day values as a JSON array of `[day, "amount"]` pairs in `dayValuesJson`, encoded and decoded in `RoomInsightRepository`. Day order stays stable and each amount stays an exact decimal string. There are no Room `TypeConverter`s; every column is already a primitive or a canonical string.

## Preferences and device state

`UserPreferencesRepository` stores settings that should not be normalised into the financial database:

- Pay-cycle start day, constrained to 1 through 28.
- Base currency, profile name, theme preference, health-score preference, and reminder preference.
- CSV/XLSX import profiles and receipt-category overrides.
- Backup metadata such as the last successful Android backup date.

Biometric enrollment, PIN verifier material, failed-attempt counters, encryption keys, and cloud account credentials stay in Android Keystore or other platform security storage. They are not DataStore values to export or restore.

## Repository boundary

Every repository below is an interface with a single `Room*` implementation, constructed in `PersonalFinanceApplication`.

| Repository | DAOs | Responsibilities |
| --- | --- | --- |
| `TransactionRepository` | `TransactionDao`, `RecurrenceRuleDao` | Observe all transactions, upsert, delete, atomic batch insert, and close a recurrence rule while deleting this-and-future occurrences. |
| `CategoryRepository` | `CategoryDao`, `RecurrenceRuleDao` | Category CRUD with name validation and budget encoding, default-category seeding, and clearing recurrence references on delete. |
| `GoalRepository` | `GoalDao` | Goal CRUD. Progress stays derived from linked transactions. |
| `CreditCardRepository` | `CreditCardDao` | Credit-card CRUD, listed by name like the frozen sort descriptor. |
| `RecurrenceRepository` | `RecurrenceRuleDao`, `TransactionDao` | Rule creation, occurrence materialization, and this-and-future updates. It intentionally exposes no read method; rules are read through the DAO. |
| `InsightRepository` | `HealthScoreSnapshotDao`, `DailyForecastCacheDao` | Health-score history and forecast-cache persistence. Financial calculations remain pure domain services. |
| `ReceiptMappingRepository` | `MerchantCategoryMappingDao` | Learned merchant-to-category mappings, keyed on a merchant name normalized exactly as the frozen inferrer normalizes it. |
| `UserPreferencesRepository` | — | Typed `Flow` access to DataStore preferences and validated updates. |
| `ReceiptCategoryMapRepository` | — | Receipt concept-to-category overrides, in DataStore rather than Room. |
| `BackupRepository` | via the repositories above | Maps domain data and relevant preferences into Android backup payloads. It does not expose DAOs to cloud code. |

Repositories return immutable domain models and `Flow` streams for observed data. They are injected into ViewModels; DAOs remain implementation details. Activity type, category, date, amount, and recurring filter semantics live in `TransactionFilters` in the domain layer and are applied to the observed transaction stream, matching iOS `SearchFilters.matches`.

## Android v1 implementation order

1. Create the Room entities, converters, DAOs, database, and DataStore preferences contract.
2. Implement category and transaction repositories plus default-category seeding.
3. Add goals, recurrence, credit cards, receipt mappings, and insight persistence.
4. Translate the iOS search and pay-cycle tests before implementing Activity and Dashboard UI.
5. Add backup mapping only after the persistent data contract is covered by tests.

## Acceptance criteria for issue #83

- Every iOS persisted model has an Android entity, an explicit derived-cache designation, or a documented device-only treatment.
- No financial amount can pass through Room as a binary floating-point value.
- Deleting a category, goal, or recurrence rule preserves historical transaction records according to the documented relationship rules.
- A repository test can verify atomic batch inserts, recurrence materialization, filter semantics, and pay-cycle boundary calculations against an in-memory Room database.
- ViewModels can be written against repository interfaces without importing Room or DataStore types.

## Evidence

- iOS schema: `PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift`
- iOS repository contract: `PersonalFinanceTraker/PersonalFinanceTraker/Models/TransactionRepository.swift`
- iOS models: `PersonalFinanceTraker/PersonalFinanceTraker/Models/`
- iOS preferences: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/AppSettings.swift`
