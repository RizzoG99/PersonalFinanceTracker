import Testing
import Foundation
@testable import PersonalFinanceTraker

struct RestoreServiceTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeService(with payload: BackupPayload) -> BackupService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = TestBackupStorage(url: dir)
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        _ = try? service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")],
            recurrenceRules: [],
            now: date(2026, 1, 1)
        )
        return service
    }

    @Test func restoreLatestThrowsWhenNoBackupExists() async {
        let repo = MockTransactionRepository()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = BackupService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        await #expect(throws: RestoreService.RestoreError.noBackupFound) {
            try await RestoreService.restoreLatest(repo: repo, backupService: service)
        }
    }

    @Test func restoreLatestWipesThenRestoresFromNewestBackup() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = BackupService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        let ruleId = UUID()
        _ = try service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 5), amount: -42, note: "Lunch", category: "Food", recurrenceRuleId: ruleId)],
            recurrenceRules: [.test(id: ruleId, frequency: .monthly, interval: 1, startDate: date(2026, 1, 1), amount: -1200, category: "Housing")],
            now: date(2026, 1, 6)
        )

        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2020, 1, 1), amount: -1, category: "Stale")]

        try await RestoreService.restoreLatest(repo: repo, backupService: service)

        #expect(repo.deleteAllTransactionsCalledCount == 1)
        #expect(repo.deleteAllRecurrenceRulesCalledCount == 1)
        #expect(repo.addRecurrenceRuleCalls.count == 1)
        #expect(repo.addRecurrenceRuleCalls[0].id == ruleId)
        #expect(repo.addCalledCount == 1)
    }
}
