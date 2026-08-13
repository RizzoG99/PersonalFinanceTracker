import Testing
import Foundation
import CryptoKit
@testable import PersonalFinanceTraker

final class TestSchedulingSettings: BackupSchedulingSettings {
    var lastBackupDate: Date?
}

struct BackupSchedulerTests {
    // ponytail: see BackupServiceTests' matching comment — an injected per-instance
    // key avoids racing on BackupCrypto's process-global Keychain account under
    // Swift Testing's default parallel execution.
    private let backupKey = SymmetricKey(size: .bits256)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeService(storage: TestBackupStorage, maxBackupsKept: Int = 3) -> BackupService {
        BackupService(storage: storage, maxBackupsKept: maxBackupsKept, keyProvider: { backupKey })
    }

    private func makeTempService() -> BackupService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return makeService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3)
    }

    @Test func runsBackupWhenNeverBackedUpBefore() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let settings = TestSchedulingSettings()
        let service = makeTempService()

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2))

        #expect(settings.lastBackupDate == date(2026, 1, 2))
        #expect(service.listBackups().count == 1)
    }

    @Test func skipsBackupWhenLastBackupIsFresh() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let settings = TestSchedulingSettings()
        settings.lastBackupDate = date(2026, 1, 2, 9)
        let service = makeTempService()

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2, 10))

        #expect(service.listBackups().isEmpty)
    }

    @Test func doesNotUpdateLastBackupDateWhenStoreIsEmpty() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = []
        let settings = TestSchedulingSettings()
        let service = makeTempService()

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2))

        #expect(settings.lastBackupDate == nil)
        #expect(service.listBackups().isEmpty)
    }

    @Test func doesNotUpdateLastBackupDateWhenICloudUnavailable() async {
        let repo = MockTransactionRepository()
        repo.stubbedTransactions = [.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let settings = TestSchedulingSettings()
        let service = makeService(storage: TestBackupStorage(url: nil), maxBackupsKept: 3)

        await BackupScheduler.runIfNeeded(repo: repo, settings: settings, backupService: service, now: date(2026, 1, 2))

        #expect(settings.lastBackupDate == nil)
    }
}
