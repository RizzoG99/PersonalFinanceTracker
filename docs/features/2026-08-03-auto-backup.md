# Feature: Auto-Backup & Restore

## Problem
If a user accidentally deletes the app, all their transaction and recurrence data is lost with no way to recover it.

## Approach
Periodically export all data (transactions + recurrence rules) as plaintext JSON, written to the app's iCloud Drive ubiquity container. The backup runs opportunistically when the app comes to the foreground, if the last backup is more than 24h old — no background task, no CloudKit. Restore is a manual action in Profile's DATA section that wipes the local store and re-inserts from the backup via the existing repository. This reuses existing `TransactionSnapshot`/`RecurrenceRuleSnapshot` and repository bulk methods instead of introducing new abstractions.

Rejected alternatives:
- **CloudKit** instead of iCloud Drive — much more setup (container/record types) for what is just one JSON blob.
- **BGTaskScheduler** instead of foreground-check — needs a background-mode entitlement and scheduling boilerplate; iOS doesn't guarantee timely execution anyway, and foreground-check is good enough since the backup only needs to predate an eventual app delete.
- **App-layer encryption (CryptoKit + Keychain)** — considered and rejected. The obvious key-storage choice (iCloud Keychain, so the key survives the same disaster as the backup) puts the key right next to the file in the same iCloud account — they sync and get compromised together. That buys protection against exactly one thin, mostly theoretical threat (Apple-side/iCloud-account access to the Drive file specifically, not the Keychain), while introducing a real data-loss failure mode of its own (synced file + unsynced key = permanently unreadable backup) into a feature whose only job is preventing data loss. iCloud Drive is already encrypted in transit and at rest by Apple; that's the trust boundary this backup lives inside. // ponytail: rely on iCloud's own encryption; add app-layer crypto only if backups ever need to leave the Apple trust boundary (e.g. exporting to a third-party store).
- **Local Documents copy alongside iCloud** — considered and rejected. It's sandboxed and deleted along with the app, i.e. it protects against nothing in the one scenario this feature exists for (app deletion). It would only add failure surface (write errors, a second status branch) with no corresponding benefit.

## Key decisions
- **Format**: JSON encoding of `TransactionSnapshot` + `RecurrenceRuleSnapshot` (already `Sendable` value types), not raw SwiftData models (not `Codable`) and not a raw `.sqlite` store copy (too coupled to SwiftData's on-disk schema across migrations).
- **Storage**: iCloud Drive ubiquity container only, plaintext JSON. No local copy, no app-layer encryption (see rejected alternatives above for why).
- **Trigger**: check `lastBackupDate` (stored in `AppSettings`/UserDefaults) on scene-become-active; if >24h stale, run backup inline.
- **Never back up an empty store**: skip the auto-backup entirely if local transaction count is 0. This is the critical guard — see Failure modes below for the exact bug it prevents.
- **Keep the last N backups** (e.g. 3, timestamped filenames like `backup-2026-08-03T09-00.json`), not a single overwritten file. With encryption gone, this rotation is the actual safety net: if a bad/partial backup ever gets written, the previous one is still there to restore from. Prune oldest beyond N on each successful write.
- **Restore**: manual, user-initiated from Profile > DATA, requires explicit confirmation. **Wipe-and-replace**, not merge: delete all local transactions/recurrence rules, then decode the backup and call `repo.addBatch()` / recurrence rule insert methods. Merge/dedupe was considered and rejected — `TransactionSnapshot.id` is a SwiftData `PersistentIdentifier`, which is not a stable identity across a reinstalled store, so transactions can't be reliably deduped against existing data. (`RecurrenceRuleSnapshot` does carry a stable UUID, but having dedupe-by-id work for rules and not transactions would be a confusing, inconsistent restore behavior — wipe-and-replace is coherent across both.)
- **Which backup restore picks**: always the newest valid backup among the N kept. No backup-picker UI — YAGNI until someone actually asks to restore an older one; newest-wins is the right default for "app was just reinstalled."
- **Atomic writes**: write each backup with `Data.write(to:options:.atomic)` (temp file + rename under the hood). This means a backgrounded/killed app mid-write can never leave a torn/truncated JSON file in the container. It changes what the N-backup rotation is actually insurance against: with atomic writes, rotation only needs to cover a logically-bad-but-complete backup (the empty-store case, already guarded above), not a physically corrupt one — cheaper insurance than the rotation itself.
- Threat model: this backup's confidentiality is whatever iCloud Drive already provides (Apple's in-transit/at-rest encryption for the user's own iCloud account). No additional app-layer protection beyond that.
- **Decided: dedicated backup DTOs, not `TransactionSnapshot`/`RecurrenceRuleSnapshot` directly.** Confirmed neither snapshot type is `Codable` today (both are only `Sendable, Hashable, Identifiable`), so this was never a "just encode the snapshot" case anyway. Define small `BackupTransaction`/`BackupRecurrenceRule` `Codable` structs carrying only the fields restore actually needs (timestamp, amount, note, category, currencyCode, goalId, recurrenceRuleId for transactions; the full rule fields keyed by the rule's stable UUID for recurrence rules) — no `PersistentIdentifier` in the JSON shape at all, since wipe-and-replace restore has no use for it and it'd be dead weight baked into every backup going forward. Settling this now avoids changing the on-disk JSON shape after real backups exist in the wild.

## Failure modes
- **Reinstall-clobber race (critical — the reason the empty-store guard exists)**: without a guard, the exact scenario this feature exists for breaks it. User deletes the app and reinstalls (or gets a new device) → local store is empty → `lastBackupDate` is `nil` (fresh `UserDefaults`) → trivially reads as ">24h stale" → foreground trigger fires a backup → writes an empty JSON over the one good backup in iCloud Drive → user taps Restore → restores nothing. The auto-trigger races the user's own chance to restore, and wins, and wipe-and-replace + a single backup file means there's no merge or history left to recover from. Fixed by: never auto-backing-up an empty local store, and keeping a short backup history (both above) instead of one overwritable file.
- **No iCloud account signed in**: `FileManager.url(forUbiquityContainerIdentifier:)` returns `nil` — there's nowhere to write, so no backup happens at all. This is now a single clear state rather than a partially-useful local fallback: **no iCloud → no backup, full stop**.
- **iCloud full / write fails**: backup write fails; catch the error without blocking or crashing, and don't update `lastBackupDate` so the next foreground check retries.
- **Status indicator collapses to one bit**: is there a successfully synced iCloud backup file, yes/no (e.g. "Last backup: today, ☁️" vs "⚠️ Not backed up — enable iCloud to protect against app deletion"). No combined file+key state to reason about anymore.
- **Restore onto a non-empty store**: handled by making restore wipe-and-replace with an explicit confirmation dialog ("This will replace all current data with the backup from <date>") rather than silently merging or doubling data.

## Architecture notes
Where this fits in the existing codebase:
- **New**: `BackupService.swift` (e.g. under `/Utilities/`) — encode snapshots to JSON, write/read the iCloud ubiquity container file.
- **New**: restore flow — confirmation UI, then wipe local transactions/recurrence rules, decode backup, call `ITransactionRepository.addBatch()` and the recurrence rule insert method.
- **Modify**: `ProfileView.swift` — add "Backup & Restore" entries (with status line) to the existing DATA section (next to Import/Export).
- **Modify**: `AppSettings.swift` — add `lastBackupDate`.
- **Modify**: app's scene/lifecycle entry point — trigger backup check on foreground.
- **Modify**: `PersonalFinanceTraker.entitlements` — add iCloud Drive (ubiquity container) capability; currently empty.
- No SwiftData schema changes required — this feature is additive tooling around existing models.

## Where to start
Add the iCloud Drive entitlement, then write `BackupService` with the encode + write-to-ubiquity-container path — including the empty-store skip guard from the start, not as a follow-up — verified by checking the file lands in the Files app under the app's iCloud Drive folder.
