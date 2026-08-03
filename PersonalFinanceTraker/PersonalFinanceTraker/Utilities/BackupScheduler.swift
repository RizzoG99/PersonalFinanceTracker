import Foundation

protocol BackupSchedulingSettings: AnyObject {
    var lastBackupDate: Date? { get set }
}

enum BackupScheduler {
    static let staleInterval: TimeInterval = 24 * 60 * 60

    static func runIfNeeded(
        repo: ITransactionRepository,
        settings: BackupSchedulingSettings,
        backupService: BackupService,
        now: Date = Date()
    ) async {
        if let last = settings.lastBackupDate, now.timeIntervalSince(last) < staleInterval {
            return
        }
        guard let transactions = try? await repo.fetchAll() else { return }
        let rules = (try? await repo.fetchActiveRecurrenceRules()) ?? []

        do {
            try backupService.writeBackup(transactions: transactions, recurrenceRules: rules, now: now)
            settings.lastBackupDate = now
        } catch {
            // BackupError.emptyStore (fresh reinstall, nothing to back up yet) or .iCloudUnavailable —
            // skip silently and leave lastBackupDate untouched so the next foreground check retries.
        }
    }
}
