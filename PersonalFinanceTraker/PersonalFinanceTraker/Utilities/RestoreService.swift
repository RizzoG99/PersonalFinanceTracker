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

        // Travels first: restored transactions carry a raw travelId, so the
        // folders must exist (with their original ids) before the batch lands.
        try await repo.replaceAllTravels(
            (payload.travels ?? []).map {
                TravelSnapshot(id: $0.id, name: $0.name, symbolName: $0.symbolName, createdAt: $0.createdAt)
            }
        )

        for input in BackupMapper.makeRecurrenceRuleInputs(from: payload.recurrenceRules) {
            try await repo.addRecurrenceRule(input)
        }

        try await repo.addBatch(BackupMapper.makeTransactionInputs(from: payload.transactions))
    }
}
