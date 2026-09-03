# Feature: Native Android App

## Decision summary

Build a separate, fully native Android app in Kotlin and Jetpack Compose in this repository. The first Android release targets current iOS feature parity, except for the explicitly deferred iOS-to-Android onboarding migration enhancement.

The delivery work is tracked in the `Android Native` GitHub Project. This document, the Android roadmap, and the shared parity and transfer documents are the durable product record.

## Problem and outcome

People who use Personal Finance Tracker on Android cannot currently use the product. The outcome is a reliable Android app that supports the same financial workflows and protects financial data to the same standard as iOS.

## User experience

Android users can manage their finances with the same core and advanced workflows available on iOS. The interface follows Android conventions while preserving equivalent behaviour, calculations, and data protection.

Android offers the regular CSV and Excel transaction-import flow, including column and category mapping, at any time.

## Key states and edge cases

- CSV and Excel imports retain their mapping, validation, and error states at any point in the Android user journey.
- Android mirrors iOS backup capability with encrypted Google Drive backup, manual backup and restore, status, retention, and clear unavailable or failed states.

## MVP

- Full parity with the current iOS product at Android v1, tracked explicitly in the parity matrix.
- Kotlin, Jetpack Compose, Room, MVVM/repository architecture, Android-native accessibility, and Android test coverage.
- Core finance, insights, goals, budgets, credit cards, import/export, receipt workflows, security, profile, and backup/restore parity.
- Ongoing CSV and Excel import/export parity.
- Encrypted Google Drive backup and restore parity.

## Non-goals

- A direct Swift/SwiftUI code conversion.
- iOS-to-Android onboarding migration, automatic device-to-device transfer, QR pairing, or a WhatsApp-style live transfer in Android v1. These belong to deferred enhancement #87.
- Introducing cross-platform account sync unless it is separately approved; iCloud and Google Drive remain platform-specific backup providers.

## Product decisions

- Android v1 aims for full current iOS parity.
- The Android app is native Kotlin + Jetpack Compose, not a cross-platform framework.
- Regular CSV/XLSX imports remain available at any time, as on iOS.
- Android backup mirrors iOS backup using encrypted Google Drive storage.

## Technical considerations

- The iOS application currently uses SwiftUI, SwiftData, and MVVM; Android should use Kotlin, Jetpack Compose, Room, ViewModels/StateFlow, and repositories.
- Financial calculations, money representation, category rules, import rules, and archive schema need platform-independent specifications before either platform changes them.
- The current iOS encrypted backup relies on an iCloud Keychain key. Android needs an equivalent encrypted Google Drive recovery mechanism, independent of iCloud.
- Google Drive backup needs Android account, consent, encryption-key, recovery, and restore decisions that preserve the stated no-data-loss and no-silent-overwrite expectations.

## Success signals

- Every current iOS capability has a documented Android status: matched, planned, deferred by explicit decision, or intentionally platform-specific.
- Android CSV/XLSX import-export and backup-restore pass the same functional scenarios as iOS.
- Android reaches Google Play closed testing with no unresolved parity-blocking defects.

## Open questions

- Google Drive integration and authentication model.
- Minimum Android version, device support policy, and final Material 3 visual direction.
- The deferred migration archive scope, encryption contract, and guided-transfer experience in enhancement #87.

## Where to start

Create and validate the iOS-to-Android parity matrix and Android data contract. They determine the Android database, backup behaviour, acceptance tests, and the actual size of the v1 release.
