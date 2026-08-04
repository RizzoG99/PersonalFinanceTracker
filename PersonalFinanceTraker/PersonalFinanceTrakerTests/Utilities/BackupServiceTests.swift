import Testing
import Foundation
@testable import PersonalFinanceTraker

struct BackupServiceTests {
    private func makeTempStorage() -> (storage: TestBackupStorage, url: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (TestBackupStorage(url: dir), dir)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func writeBackupCreatesAJSONFileInTheContainer() throws {
        let (storage, dir) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2))

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test func writeBackupThrowsWhenTransactionsAreEmpty() {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)

        #expect(throws: BackupService.BackupError.emptyStore) {
            try service.writeBackup(transactions: [], recurrenceRules: [], now: date(2026, 1, 1))
        }
    }

    @Test func writeBackupThrowsWhenICloudUnavailable() {
        let storage = TestBackupStorage(url: nil)
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        #expect(throws: BackupService.BackupError.iCloudUnavailable) {
            try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        }
    }

    @Test func newestBackupReturnsTheMostRecentlyWrittenFile() throws {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        let first = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))
        let second = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2, 9, 0))

        #expect(service.newestBackup() == second)
        #expect(service.newestBackup() != first)
    }

    @Test func writeBackupPrunesBeyondMaxBackupsKept() throws {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 2)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2, 9, 0))
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 3, 9, 0))

        #expect(service.listBackups().count == 2)
    }

    @Test func readBackupDecodesWhatWasWritten() throws {
        let (storage, _) = makeTempStorage()
        let service = BackupService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, note: "Lunch", category: "Food")]

        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        let payload = try service.readBackup(at: url)

        #expect(payload.transactions.count == 1)
        #expect(payload.transactions[0].note == "Lunch")
    }
}
