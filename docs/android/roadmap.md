# Android Native Roadmap

## Objective

Release a native Kotlin and Jetpack Compose Android version of Personal Finance Tracker to Google Play closed testing with full parity for the current iOS product, documented data portability, and equivalent protection for financial data.

## Delivery milestones

### 0. Product and data contract

- Audit every current iOS feature, workflow, entity, calculation, and edge case.
- Publish the parity matrix and classify each item as matched, planned, blocked, or intentionally platform-specific.
- Define money, date, category, recurrence, import/export, archive-version, and privacy rules independent of iOS and Android implementation.
- Define acceptance scenarios that both apps must pass.

**Done when:** Android v1 scope and its data contract have no unrecorded assumptions.

### 1. Android foundation

- Create the Android Studio project in `Android/` without moving the existing iOS project.
- Establish Kotlin, Jetpack Compose, Material 3, Room, MVVM/repositories, navigation, localization, dependency injection, test conventions, and CI.
- Build the app theme, reusable components, accessibility baseline, and empty/loading/error states.

**Done when:** a signed debug app can run, persist test data, navigate between shell screens, and pass its foundation test suite.

### 2. Core finance parity

- Profile and pay-cycle configuration.
- Categories and category settings.
- Dashboard and transaction activity history.
- Add, edit, delete, undo, search, filtering, and recurring-transaction workflows.
- Correct monetary calculations and period boundaries.

**Done when:** a tester can complete ordinary daily finance tracking with results matching iOS for the same dataset.

### 3. Advanced finance parity

- Insights, financial health, forecast, trends, charts, and goals.
- Budgets, spending progress, and related alerts or states.
- Credit-card workflows and utilization.
- Receipt capture and any current feature-discovery or supporting workflows in iOS.

**Done when:** all current iOS analytical and advanced-finance workflows have Android acceptance coverage and parity status.

### 4. Import, export, and iOS migration

- CSV/XLSX transaction import and export, including column mapping and category mapping.
- Versioned portable transfer archive for all Android-v1 parity data.
- iOS archive export and Android onboarding-only archive import.
- Passphrase protection, validation, preview, rollback, version errors, and recovery guidance.

**Done when:** a tester can transfer a representative iOS dataset into a new Android installation and can still use ongoing CSV/XLSX imports after setup.

### 5. Security and backup parity

- Biometric and PIN protection.
- Destructive-action and delete-all-data safeguards.
- Encrypted Google Drive backup, restore, status, retention, and failure handling.
- Privacy disclosures and secure local-storage review.

**Done when:** protected data and recovery behaviour meet the documented iOS-equivalent scenarios.

### 6. Release readiness

- Device, screen-size, dark-mode, large-text, TalkBack, offline, and error-state verification.
- Unit, integration, UI, and cross-platform scenario tests.
- Play Store listing, privacy policy, app signing, internal test, closed test, crash monitoring, and release checklist.

**Done when:** the Android app is accepted for closed testing with no open critical parity or security defects.

### 7. Post-launch parity maintenance

- Review every iOS feature change against Android before it is considered complete.
- Add or update a parity item and shared documentation for every changed cross-platform rule.
- Track future device-to-device transfer separately from the v1 archive flow.

## GitHub Project conventions

- Project: `Android Native`
- Status: `Backlog`, `Ready`, `In progress`, `Blocked`, `In review`, `Done`
- Milestone: `0 Contract`, `1 Foundation`, `2 Core parity`, `3 Advanced parity`, `4 Data transfer`, `5 Security and backup`, `6 Release`, `7 Maintenance`
- Area: `Architecture`, `UI`, `Data`, `Transactions`, `Categories`, `Insights`, `Budgets`, `Credit`, `Import/Export`, `Security`, `Quality`, `Release`
- Parity: `Not assessed`, `Planned`, `In progress`, `Matched`, `Platform-specific`, `Deferred`

Use the project roadmap view for milestones, the board view for daily work, and the parity view to expose gaps before release.
