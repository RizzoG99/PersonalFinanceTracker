# Cross-Platform Transfer Contract

> **Status: deferred enhancement.** This contract is intentionally outside Android v1 and is tracked in GitHub issue #87. It remains here for the future work; Android v1 retains CSV/XLSX transaction import and export only.

## Purpose

Allow an iOS user to move their Personal Finance Tracker data to a new Android installation without exposing the data in a plaintext attachment or merging it into an existing Android dataset.

The transferable-data inventory and cross-platform invariants are defined in `android-v1-data-contract.md`.

## Agreed experience

1. In iOS, the user chooses to export an Android transfer archive and chooses a passphrase.
2. The app writes a versioned encrypted archive.
3. The user shares or saves it through a channel they control, such as email, Files, Drive, or AirDrop.
4. During first-time Android setup, the user selects the archive and enters its passphrase.
5. Android validates, previews, and imports the archive only into an empty finance database.

## Invariants

- The archive is encrypted with a user-chosen passphrase.
- The passphrase is not stored, transmitted to a service, recoverable, or included in the archive.
- Wrong passphrase, malformed data, unsupported version, or interrupted import never creates partial Android data.
- Archive import is available only before Android creates financial data; it never merges with an existing dataset.
- The archive uses an explicit version and migration policy.
- The archive eventually includes every data entity required for Android v1 parity, not only transactions.

## Separate flows

- CSV/XLSX import/export remains the normal, transaction-oriented portability feature and is available after onboarding.
- iOS encrypted backup remains an iCloud-specific recovery mechanism.
- Android encrypted backup mirrors that capability through Google Drive.
- The portable transfer archive is a third, cross-platform mechanism; it must not depend on an iCloud Keychain key.

## Design work remaining

- Archive extension and schema.
- Entity inventory and stable identifiers.
- Encryption algorithm, authenticated metadata, password-based key derivation, and version negotiation.
- Preview, validation, transactionality, and rollback rules.
- iOS export UX and Android onboarding UX.
- Test fixtures and interoperability tests.
