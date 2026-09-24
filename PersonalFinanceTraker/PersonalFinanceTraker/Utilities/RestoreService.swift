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

        // Categories themselves are never deleted/restored — only transactions and rules —
        // so relink against whatever already exists in the store.
        let categories = try await repo.fetchCategories()

        for input in BackupMapper.makeRecurrenceRuleInputs(from: payload.recurrenceRules, categories: categories) {
            try await repo.addRecurrenceRule(input)
        }

        try await repo.addBatch(BackupMapper.makeTransactionInputs(from: payload.transactions, categories: categories))
    }
}
