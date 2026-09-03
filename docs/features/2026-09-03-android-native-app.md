# Feature: Native Android App

## Decision summary

Build a separate, fully native Android app in Kotlin and Jetpack Compose in this repository. The first Android release targets full parity with the current iOS app, rather than a reduced feature set.

The delivery work is tracked in the `Android Native` GitHub Project. This document, the Android roadmap, and the shared parity and transfer documents are the durable product record.

## Problem and outcome

People who use Personal Finance Tracker on Android cannot currently use the product. The outcome is a reliable Android app that supports the same financial workflows and protects financial data to the same standard as iOS.

Existing iOS users can move to Android during Android onboarding by exporting an encrypted transfer archive, sending or saving it through a channel they choose, and importing it into a clean Android installation.

## User experience

Android users can manage their finances with the same core and advanced workflows available on iOS. The interface follows Android conventions while preserving equivalent behaviour, calculations, and data protection.

For a one-time iOS migration, onboarding offers **Transfer from iPhone** before any Android financial data has been created:

1. The user exports a passphrase-protected transfer archive from iOS.
2. They send, save, or otherwise make the file available on the Android device.
3. Android lets the user choose the archive and enter its passphrase.
4. Android validates the archive, presents a summary of the data to be imported, and imports it into its empty local database.

After setup, Android continues to offer the regular CSV and Excel transaction-import flow, including column and category mapping, independently of the migration flow.

## Key states and edge cases

- Migration is visible only during first-time setup; it never merges into an existing Android financial dataset.
- A wrong passphrase, corrupt archive, unsupported archive version, or incomplete import must leave the Android database unchanged and explain the recovery path.
- The user can skip migration and start with an empty Android app.
- CSV and Excel imports remain available after onboarding and retain their own mapping, validation, and error states.
- Android mirrors iOS backup capability with encrypted Google Drive backup, manual backup and restore, status, retention, and clear unavailable or failed states.

## MVP

- Full parity with the current iOS product at Android v1, tracked explicitly in the parity matrix.
- Kotlin, Jetpack Compose, Room, MVVM/repository architecture, Android-native accessibility, and Android test coverage.
- Core finance, insights, goals, budgets, credit cards, import/export, receipt workflows, security, profile, and backup/restore parity.
- Onboarding-only encrypted iOS-to-Android migration.
- Ongoing CSV and Excel import/export parity.
- Encrypted Google Drive backup and restore parity.

## Non-goals

- A direct Swift/SwiftUI code conversion.
- Automatic device-to-device transfer, QR pairing, or a WhatsApp-style live transfer in Android v1.
- Merging an iOS transfer archive into an existing Android dataset.
- Introducing cross-platform account sync unless it is separately approved; iCloud and Google Drive remain platform-specific backup providers.

## Product decisions

- Android v1 aims for full current iOS parity.
- The Android app is native Kotlin + Jetpack Compose, not a cross-platform framework.
- iOS-to-Android transfer uses a versioned, user-selected passphrase-protected archive.
- The passphrase is not stored or recoverable; an archive cannot be imported without it.
- Transfer is offered only during first-time setup, before Android has local financial data.
- Regular CSV/XLSX imports remain available at any time, as on iOS.
- Android backup mirrors iOS backup using encrypted Google Drive storage.

## Technical considerations

- The iOS application currently uses SwiftUI, SwiftData, and MVVM; Android should use Kotlin, Jetpack Compose, Room, ViewModels/StateFlow, and repositories.
- Financial calculations, money representation, category rules, import rules, and archive schema need platform-independent specifications before either platform changes them.
- The current iOS encrypted backup relies on an iCloud Keychain key, so it is not a portable Android migration format. A separate cross-platform archive and encryption contract is required.
- The current iOS CSV/XLSX export flow is transaction-focused. The migration archive must explicitly version and include every supported parity entity.
- Google Drive backup needs Android account, consent, encryption-key, recovery, and restore decisions that preserve the stated no-data-loss and no-silent-overwrite expectations.

## Success signals

- Every current iOS capability has a documented Android status: matched, planned, deferred by explicit decision, or intentionally platform-specific.
- A tester can complete the iOS export and Android onboarding import without data loss using a passphrase they choose.
- Android CSV/XLSX import-export and backup-restore pass the same functional scenarios as iOS.
- Android reaches Google Play closed testing with no unresolved parity-blocking defects.

## Open questions

- Exact portable archive schema, encryption algorithm, key derivation, and supported backward-compatibility policy.
- Google Drive integration and authentication model.
- The complete inventory of data entities that must be included in migration and backup.
- Minimum Android version, device support policy, and final Material 3 visual direction.
- Whether a future guided device-to-device transfer experience is worth building after launch.

## Where to start

Create and validate the iOS-to-Android parity matrix and cross-platform data contract. They determine the Android database, the migration archive, acceptance tests, and the actual size of the v1 release.
