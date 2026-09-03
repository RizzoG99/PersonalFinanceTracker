# Android v1 Data Contract

## Status and purpose

This is the source-audited starting contract for Android v1. It defines what the Android database, iOS-to-Android transfer archive, and Android backup must preserve to achieve current iOS parity. It is intentionally separate from any database or encryption implementation.

The wire schema, encryption algorithm, password-based key derivation, and compatibility policy remain implementation decisions; they must conform to the invariants below.

## Source audit

The authoritative iOS SwiftData schema is declared in `App/AppContainer.swift`. The app currently persists these models:

| Data | Current iOS source | Android v1 database | Transfer archive | Notes |
| --- | --- | --- | --- | --- |
| Transactions | `TransactionModel` | Required | Required | Current model has no portable UUID; SwiftData's persistent ID cannot cross platforms. |
| Categories | `CategoryModel` | Required | Required | The model has a stable UUID, name, icon, type, color token, optional monthly budget, and currency. |
| Goals | `GoalModel` | Required | Required | Transactions and recurrence rules can refer to a goal UUID. |
| Credit cards | `CreditCardModel` | Required | Required | Name, last four digits, balance, limit, color, and currency are user data. |
| Recurrence rules | `RecurrenceRule` | Required | Required | Includes cadence, active dates, materialization cursor, transaction template, goal, and category relationship. |
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

## Existing backup is not a migration archive

The iOS `.pftbackup` payload currently contains only transactions and recurrence rules. It is encrypted with an iCloud Keychain-backed key. It cannot be imported by Android and is not a substitute for the portable transfer archive.

The portable archive must be a separate format. It includes the required data above, is encrypted with a user-chosen passphrase, and is available only for first-time Android onboarding. CSV/XLSX continue to be transaction-focused imports available after onboarding.

## Cross-platform invariants

- Money is never encoded as a binary floating-point value. Keep the signed decimal amount exact in a locale-independent representation. Expenses are negative; income is positive.
- Every transferable entity needs a stable archive UUID. Current category, goal, credit-card, and recurrence-rule UUIDs can be preserved. Transactions need a new portable identifier strategy because their current SwiftData persistent IDs are not transferable.
- Relationships use those stable archive UUIDs. Android must not rely on display names, SwiftData IDs, or icon names as foreign keys.
- The archive uses an explicit format identifier, schema version, creation timestamp, and authenticated metadata before any payload records are accepted.
- Timestamps use a documented ISO 8601 representation. Calendar-based business rules must be tested at pay-cycle boundaries and daylight-saving changes.
- An archive import validates the complete archive before writing. If validation, decryption, mapping, or persistence fails, Android leaves the onboarding database empty.
- Import is allowed only before Android has financial data. It creates no merge or deduplication behaviour.
- Imported categories must be available before transactions and recurrence rules are linked; imported goals must exist before their references are resolved.
- Default categories are seeded only when the transfer archive does not provide a category dataset.

## Required archive sections

The v1 archive must have sections for:

1. Metadata: format identifier, schema version, creation timestamp, producing app/version, and the minimum Android version supported by the archive.
2. Profile and preferences: pay-cycle start day, base currency, user name, import and receipt mappings, health-score preference, and reminder preference.
3. Categories, goals, credit cards, merchant-category mappings, and health-score history.
4. Recurrence rules followed by transactions, preserving their stable references.

It must not contain PIN material, biometric state, keychain data, cloud-provider tokens, or any device-specific encryption key.

## Acceptance scenarios

The contract is accepted only when these scenarios pass on both platforms:

- A representative iOS dataset preserves exact transaction amounts, dates, notes, categories, goals, recurrence links, budgets, and credit-card balances after Android onboarding import.
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
