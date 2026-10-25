import Testing
import Foundation
import CryptoKit
@testable import PersonalFinanceTraker

struct RestoreServiceTests {
    // ponytail: see BackupServiceTests' matching comment — an injected per-instance
    // key avoids racing on BackupCrypto's process-global Keychain account under
    // Swift Testing's default parallel execution.
    private let backupKey = SymmetricKey(size: .bits256)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeService(storage: TestBackupStorage, maxBackupsKept: Int = 3) -> BackupService {
        BackupService(storage: storage, maxBackupsKept: maxBackupsKept, keyProvider: { backupKey })
    }

    @Test func restoreLatestThrowsWhenNoBackupExists() async {
        let repo = MockTransactionRepository()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = makeService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        await #expect(throws: RestoreService.RestoreError.noBackupFound) {
            try await RestoreService.restoreLatest(repo: repo, backupService: service)
        }
    }

    @Test func restoreLatestWipesThenRestoresFromNewestBackup() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = makeService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

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

    // #177: the backup carries only category names and restore relinks to the categories already
    // in the store. It must never write categories, or a user's icon/color choices (including the
    // newer catalog entries) would be rewritten by a restore.
    @Test func restoreNeverWritesCategories() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = makeService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        _ = try service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 5), amount: -80, note: "Tires", category: "Moto")],
            recurrenceRules: [],
            now: date(2026, 1, 6)
        )

        let repo = MockTransactionRepository()
        repo.stubbedCategories = [.test(name: "Moto", systemImage: "motorcycle.fill", colorToken: "categoryBrown")]

        try await RestoreService.restoreLatest(repo: repo, backupService: service)

        #expect(repo.addCategoryCalls.isEmpty)
        #expect(repo.addCalledCount == 1)
    }

    @Test func restoreLatestRethrowsWhenRepositoryFails() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = makeService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)

        _ = try service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 5), amount: -42, note: "Lunch", category: "Food")],
            recurrenceRules: [],
            now: date(2026, 1, 6)
        )

        let repo = MockTransactionRepository()
        repo.shouldThrow = true

        await #expect(throws: MockTransactionRepository.MockError.forced) {
            try await RestoreService.restoreLatest(repo: repo, backupService: service)
        }
    }
}
