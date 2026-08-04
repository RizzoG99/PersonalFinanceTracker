import Foundation

enum RestoreService {
    enum RestoreError: Error, Equatable {
        case noBackupFound
    }

    static func restoreLatest(repo: ITransactionRepository, backupService: BackupService) async throws {
        guard let url = backupService.newestBackup() else { throw RestoreError.noBackupFound }
        let payload = try backupService.readBackup(at: url)

        try await repo.deleteAllTransactions()
        try await repo.deleteAllRecurrenceRules()

        for input in BackupMapper.makeRecurrenceRuleInputs(from: payload.recurrenceRules) {
            try await repo.addRecurrenceRule(input)
        }

        try await repo.addBatch(BackupMapper.makeTransactionInputs(from: payload.transactions))
    }
}
