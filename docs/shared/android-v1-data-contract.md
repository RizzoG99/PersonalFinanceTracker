# Android v1 Data Contract

## Status and purpose

This is the source-audited starting contract for Android v1. It defines what the Android database and Android backup must preserve to achieve current iOS parity. It is intentionally separate from any database or encryption implementation.

The cross-platform transfer-archive sections are deferred to enhancement #87 and are not Android v1 scope. They are retained here only as source-audited input for that later work.

The wire schema, encryption algorithm, password-based key derivation, and compatibility policy remain implementation decisions; they must conform to the invariants below.

## Source audit

Audited at iOS `83bc9db`, refreshed at iOS `b649dff` for #282. The authoritative iOS SwiftData schema is declared in `App/AppContainer.swift` (`b649dff:App/AppContainer.swift:24-32`). The app currently persists these models:

| Data | Current iOS source | Android v1 database | Transfer archive | Notes |
| --- | --- | --- | --- | --- |
| Transactions | `TransactionModel` | Required | Required | Current model has no portable UUID; SwiftData's persistent ID cannot cross platforms. Since `b649dff` it also carries an optional `travelId`. |
| Categories | `CategoryModel` | Required | Required | The model has a stable UUID, name, icon, type, color token, optional monthly budget, and currency. |
| Goals | `GoalModel` | Required | Required | Transactions and recurrence rules can refer to a goal UUID. |
| Travels | `TravelModel` | Required (new at `b649dff`) | Required | UUID, name, symbol name, creation date. See *Travels* below. |
| Credit cards | `CreditCardModel` | Legacy only | Exclude | Product scope excluded by the owner on 2026-10-31 (parity matrix D-01). Keep the existing `credit_cards` table and repository so legacy rows are not lost; build no UI and add no new behaviour. |
| Recurrence rules | `RecurrenceRule` | Required | Required | Includes cadence, active dates, materialization cursor, transaction template, goal, category relationship, and since `b649dff` the `autoRecord` flag. |
| Health-score history | `HealthScoreSnapshot` | Required | Required | Persist it to preserve historical insight results rather than silently discarding history. |
| Forecast cache | `DailyForecastCache` | Derived cache | Exclude | Recompute from the imported transactions and rules. |
| Learned receipt mapping | `MerchantCategoryMapping` | Required | Required | A learned merchant-to-category preference; the current iOS backup does not include it. |

Current non-SwiftData state was also audited:

| Setting or secret | Android v1 treatment | Reason |
| --- | --- | --- |
| Pay-cycle start day | Required in transfer | It changes dashboard, insight, and safe-to-spend calculations. |
| Base currency | Required in transfer | It is currently stored separately from transactions and defaults to EUR. |
| User name | Required in transfer | It is profile data. |
| Category import profiles and receipt category map | Required in transfer | They affect repeat import and receipt workflows. |
| Health-score preference | Required in transfer | It changes insight behaviour. |
| Reminder settings | Required in transfer, but Android must request its own notification permission | OS permission and scheduled notifications cannot move across platforms. |
| Theme and feature-discovery state | Exclude | These are device-specific experience preferences; Android uses its own defaults. |
| Temporary privacy mode, widget destinations, pending widget/habit actions, dismissed prompts | Exclude | These are ephemeral device state, not financial data. |
| Biometric enrollment, PIN hash, PIN failures, lockout state, iCloud/Google credentials, encryption keys | Never transfer | They are device-bound secrets or platform credentials. Android must offer its own security setup after import. |
| Backup timestamp and retention metadata | Exclude | Android backup owns its own lifecycle. |
| Safe to Spend buffer (`safeToSpendBufferPercent`, 0–20, default 5 when unset; `b649dff`) | Required in transfer | It changes the Safe to Spend figure (#298). A missing key means 5, not 0. |
| Monthly recap notification (`recapNotificationEnabled`, default on) and `recapPermissionAsked` (`b649dff`) | Transfer the preference; exclude the permission flag | Android asks for its own notification permission (#302). |
| Dismissed fixed-expense suggestions (`dismissedRecurrencePatterns`, `b649dff`) | Required in transfer | User decision ("Not fixed"); losing it brings rejected suggestions back. See *Dismissed patterns* below. |
| One-time category-name repair flag (`didRepairImportedCategoryNamesV2`, `b649dff`) | Exclude | Migration bookkeeping; Android runs its own repair once (#292). |
| What's New last-seen release (`feature_discovery_last_seen_release_*`, `b649dff`) | Exclude | Device-specific discovery state, like the tour flag above (#309). |

## Existing backup is not a migration archive

At `b649dff` the iOS `.pftbackup` payload is **version 2** (`Utilities/BackupService.swift:45`). It contains transactions, recurrence rules and, optionally, travels; it contains no categories, goals, dismissed patterns or preferences (`Models/BackupModels.swift:4-46`). It is encrypted with an iCloud Keychain-backed key. It cannot be imported by Android and is not a substitute for the portable transfer archive. Its evolution rules are recorded under *Backup evolution* below.

Any portable archive must be a separate future format. Android v1 provides CSV/XLSX transaction import and export, with the same mapping behaviour as iOS.

## Current iOS rules (`b649dff`)

Specified before any Room migration for these capabilities. Paths are relative to `PersonalFinanceTraker/PersonalFinanceTraker/` at `b649dff`. Each owning issue turns its rule into acceptance scenarios; this section is the shared data rule they must agree on.

### Travels (#284, #285)

- A travel is `id` (UUID, unique), `name`, `symbolName` (default `airplane`), `createdAt` (`Models/TravelModel.swift:16-23`).
- Membership is an optional `TransactionModel.travelId` UUID, not a relationship (`Models/TransactionModel.swift:20`). A transaction belongs to at most one travel. Recurrence rules have no travel.
- A travel only changes how Activity groups its members. Budgets, insights, the category breakdown and Safe to Spend still see every member as an ordinary transaction (`Models/TravelModel.swift:9-13`).
- Deleting a travel clears `travelId` on its members and deletes no transaction, in one save (`Models/TransactionActor.swift:467-480`). Android: the same in one Room transaction; a nullable `travelId` with `SET NULL` on delete is equivalent.
- The travel UUID must survive backup and restore, or every member is orphaned (`Models/TravelModel.swift:21-22`).

### Transfers and recurring goal contributions (#300)

- iOS stores no transaction type. A **transfer** is a transaction with a `goalId` and a negative amount; it has no category, and its `category` label is `→ <goal name>` (`Features/EditAddTransactionView/EditAddTransactionViewModel.swift:389-399`). Income is positive, expense and transfer negative.
- Transfer is offered only when at least one goal exists, unless the form is already on Transfer (`EditAddTransactionViewModel.swift:206-214`).
- A recurring transfer is a `RecurrenceRule` with `goalId` set; it keeps the goal on every occurrence (`EditAddTransactionViewModel.swift:412`).
- Money moved to a goal counts as saved, not spent, in Safe to Spend and the cycle summary (`Utilities/SafeToSpendSnapshotBuilder.swift:47`).
- Android may add an explicit type column, but it must derive the same answer as iOS for every stored row: `goalId != null && amount < 0` is a transfer. Imported rows keep the iOS rule. Recorded as technical decision C-01.

### Forecast-only rules and payment confirmation (#294, #295, #296)

- `RecurrenceRule.autoRecord` defaults to `true` (`Models/RecurrenceRule.swift:12-14`). `true` materializes transactions as before. `false` is a forecast-only fixed expense: it never inserts transactions.
- For a forecast-only rule the `lastMaterializedDate` cursor advances when a real payment matches (`Utilities/RecurrenceDetector.swift:187-209`). A payment matches when it is a negative amount with no `recurrenceRuleId`, its amount is within 15 % of the rule amount (`isSameAmount`, `:277-279`), it has the same commitment key (same `goalId`, else the same normalized note), and it falls within the match window of an expected occurrence.
- Match window: 20 % of the cycle (weekly 7, monthly 30.4, yearly 365.25 days × interval), clamped to 3–14 days (`:175-182`).
- Normalized note: lowercased, letters only, month names (EN and IT) removed (`:258-263`).
- Detection ignores amounts below €5 and clusters amounts within 15 % (`:73-78`).

### Dismissed patterns (#295, #296, #338)

- Rejecting a suggestion ("Not fixed") stores a pattern `{ note (normalized), amount, goalId? }` (`Utilities/RecurrenceDetector.swift:64-71`, `Utilities/DismissedRecurrencePatterns.swift`). A pattern suppresses a suggestion matched like an existing rule: same goal or normalized note, amount within tolerance.
- Patterns are a preference list, not Room records. They are cleared by delete-all-data (`Utilities/DataWipeService.swift:16`). Restoring hidden suggestions is future scope (#338).

### Category identity and repair (#291, #292, #293)

- A category is identified by UUID. Transactions and rules also keep a `category` name copy for display.
- Renaming a category rewrites the name copy on its linked transactions and rules in the same save (`Models/TransactionActor.swift:382-411`). Unlinked rows are left alone.
- A one-time, idempotent repair runs the same sync for every category, so rows imported with the CSV's name while linked to an app category show the app category (`TransactionActor.swift:365-380`). Android runs its own equivalent once, guarded by its own flag.
- Android keeps its `categoryId` foreign key as the identity and its `categoryLabel` as the snapshot; a rename updates both in one transaction.

### Date boundaries (#297, #298, #299, #302)

- Pay-cycle rules are unchanged between `83bc9db` and `b649dff` (`Utilities/PayCycleService.swift`): start day 1–28; a cycle runs from the start day to the day before the next start day.
- Safe to Spend, the cycle summary, the monthly recap and the calendar all use that cycle in the device calendar and time zone. Each owning issue specifies its fixtures at a cycle boundary and a daylight-saving change.

### Backup evolution (#316, #317, #318)

- iOS backup v1 → v2 added `travels` and `autoRecord`, both optional, so older backups still decode: a missing `travels` means none, a missing `autoRecord` means `true` (`Models/BackupModels.swift:11-46`).
- On restore iOS relinks categories by `name#type`, with the type taken from the amount's sign, so a transfer looks up an expense category (`BackupModels.swift:49-66`).
- Android's own backup format follows the same rule: add fields as optional with a documented default, and bump its version.
- **Open decision, owned by #317:** whether Android backup also includes goals and categories, which iOS backup omits (so a restored `goalId` can point to a missing goal). This contract does not decide it.

## Cross-platform invariants

- Money is never encoded as a binary floating-point value. Keep the signed decimal amount exact in a locale-independent representation. Expenses are negative; income is positive.
- Every transferable entity needs a stable archive UUID. Current category, goal, travel, and recurrence-rule UUIDs can be preserved. Transactions need a new portable identifier strategy because their current SwiftData persistent IDs are not transferable.
- Relationships use those stable archive UUIDs. Android must not rely on display names, SwiftData IDs, or icon names as foreign keys.
- The archive uses an explicit format identifier, schema version, creation timestamp, and authenticated metadata before any payload records are accepted.
- Timestamps use a documented ISO 8601 representation. Calendar-based business rules must be tested at pay-cycle boundaries and daylight-saving changes.
- An archive import validates the complete archive before writing. If validation, decryption, mapping, or persistence fails, Android leaves the onboarding database empty.
- Import is allowed only before Android has financial data. It creates no merge or deduplication behaviour.
- Imported categories must be available before transactions and recurrence rules are linked; imported goals must exist before their references are resolved.
- Default categories are seeded only when the transfer archive does not provide a category dataset.

## Deferred archive sections

The future migration archive must have sections for:

1. Metadata: format identifier, schema version, creation timestamp, producing app/version, and the minimum Android version supported by the archive.
2. Profile and preferences: pay-cycle start day, Safe to Spend buffer, base currency, user name, import and receipt mappings, health-score preference, reminder and monthly-recap preferences.
3. Categories, goals, travels, merchant-category mappings, dismissed fixed-expense patterns, and health-score history. Legacy credit cards are excluded (parity matrix D-01).
4. Recurrence rules followed by transactions, preserving their stable references.

It must not contain PIN material, biometric state, keychain data, cloud-provider tokens, or any device-specific encryption key.

## Acceptance scenarios

The contract is accepted only when these scenarios pass on both platforms:

- A representative iOS dataset preserves exact transaction amounts, dates, notes, categories, goals, travels, recurrence links (including `autoRecord`), and budgets after Android onboarding import.
- A wrong passphrase, tampered archive, unsupported version, missing referenced entity, or interrupted import leaves Android with no partial financial data.
- Imports at pay-cycle and daylight-saving boundaries produce the same reporting period and balance results as iOS.
- Android can restore its own encrypted Google Drive backup without relying on an iCloud key or an iOS device.
- CSV/XLSX column mapping and category mapping remain available after onboarding and do not invoke the complete migration flow.

Relevant iOS tests to translate into shared scenario fixtures include `BackupModelsTests`, `BackupServiceTests`, `RestoreServiceTests`, `CSVImportExportTests`, `CSVColumnMapperTests`, `CategoryAutoMapperTests`, `PayCycleServiceTests`, `SearchTests`, recurrence tests, and the financial-health and forecast service tests.

## Decisions still required before implementation

- The stable portable identifier design for transactions, including whether iOS adds an app-level UUID before exporting.
- The exact portable archive JSON schema, encryption algorithm, password-based key derivation parameters, and backward-compatibility policy.
- The date/time representation for calendar-only recurrence semantics across time zones.
- Whether health-score snapshots are transferred verbatim or regenerated with an explicitly accepted historical-difference policy.
- The complete serialization format for import profiles and receipt-category maps.
- Google Drive account, consent, encryption-key recovery, and backup-retention implementation details.

## Evidence

- SwiftData schema: `PersonalFinanceTraker/PersonalFinanceTraker/App/AppContainer.swift`
- Core models and repositories: `PersonalFinanceTraker/PersonalFinanceTraker/Models/`
- Settings and security: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/AppSettings.swift`, `PINService.swift`, and `BiometricAuthService.swift`
- Existing backup and restore: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/BackupService.swift`, `BackupCrypto.swift`, `RestoreService.swift`, and `Models/BackupModels.swift`
