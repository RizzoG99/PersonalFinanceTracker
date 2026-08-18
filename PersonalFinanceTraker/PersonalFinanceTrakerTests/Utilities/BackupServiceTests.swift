import Testing
import Foundation
import CryptoKit
@testable import PersonalFinanceTraker

struct BackupServiceTests {
    // ponytail: fresh per test invocation (struct is re-instantiated per @Test), so
    // each test's BackupService gets its own isolated in-memory key instead of
    // sharing BackupCrypto's process-global Keychain account — see BackupService's
    // keyProvider doc comment for why that mattered (cross-test Keychain race under
    // Swift Testing's default parallel execution).
    private let backupKey = SymmetricKey(size: .bits256)

    private func makeTempStorage() -> (storage: TestBackupStorage, url: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (TestBackupStorage(url: dir), dir)
    }

    private func makeService(storage: TestBackupStorage, maxBackupsKept: Int = 3) -> BackupService {
        BackupService(storage: storage, maxBackupsKept: maxBackupsKept, keyProvider: { backupKey })
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func writeBackupCreatesAJSONFileInTheContainer() throws {
        let (storage, dir) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2))

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test func writeBackupThrowsWhenTransactionsAreEmpty() {
        let (storage, _) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 3)

        #expect(throws: BackupService.BackupError.emptyStore) {
            try service.writeBackup(transactions: [], recurrenceRules: [], now: date(2026, 1, 1))
        }
    }

    @Test func writeBackupThrowsWhenICloudUnavailable() {
        let storage = TestBackupStorage(url: nil)
        let service = makeService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        #expect(throws: BackupService.BackupError.iCloudUnavailable) {
            try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        }
    }

    @Test func newestBackupReturnsTheMostRecentlyWrittenFile() throws {
        let (storage, _) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        let first = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))
        let second = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2, 9, 0))

        #expect(service.newestBackup() == second)
        #expect(service.newestBackup() != first)
    }

    @Test func writeBackupPrunesBeyondMaxBackupsKept() throws {
        let (storage, _) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 2)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]

        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2, 9, 0))
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 3, 9, 0))

        #expect(service.listBackups().count == 2)
    }

    @Test func readBackupDecodesWhatWasWritten() throws {
        let (storage, _) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, note: "Lunch", category: "Food")]

        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        let payload = try service.readBackup(at: url)

        #expect(payload.transactions.count == 1)
        #expect(payload.transactions[0].note == "Lunch")
    }

    @Test func encryptedWriteAndReadRoundTrip() throws {
        let (storage, _) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 3)
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, note: "Encrypted", category: "Food")]

        // Write creates an encrypted .pftbackup file
        let url = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1))
        #expect(url.pathExtension == "pftbackup")

        // Read successfully decrypts and decodes
        let payload = try service.readBackup(at: url)
        #expect(payload.version == 2)
        #expect(payload.transactions.count == 1)
        #expect(payload.transactions[0].note == "Encrypted")
    }

    @Test func legacyPlaintextJSONBackupStillRestores() throws {
        let (storage, dir) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 3)

        // Create a legacy .json backup by encoding plaintext
        let legacyPayload = BackupPayload(
            version: 1,
            createdAt: date(2026, 1, 1),
            transactions: [
                BackupTransaction(
                    timestamp: date(2026, 1, 1),
                    amount: -50,
                    note: "Legacy",
                    category: "Food",
                    currencyCode: "EUR",
                    goalId: nil,
                    recurrenceRuleId: nil
                )
            ],
            recurrenceRules: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacyPayload)

        // Write it with .json extension
        let legacyURL = dir.appendingPathComponent("backup-legacy.json")
        try legacyData.write(to: legacyURL, options: .atomic)

        // Read should successfully decode the plaintext JSON
        let readPayload = try service.readBackup(at: legacyURL)
        #expect(readPayload.version == 1)
        #expect(readPayload.transactions.count == 1)
        #expect(readPayload.transactions[0].note == "Legacy")
    }

    @Test func listBackupsIncludesBothJsonAndPftbackupExtensions() throws {
        let (storage, dir) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 10)

        // Create a legacy .json backup
        let legacyPayload = BackupPayload(
            version: 1,
            createdAt: date(2026, 1, 1),
            transactions: [
                BackupTransaction(
                    timestamp: date(2026, 1, 1),
                    amount: -10,
                    note: "",
                    category: "Food",
                    currencyCode: "EUR",
                    goalId: nil,
                    recurrenceRuleId: nil
                )
            ],
            recurrenceRules: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacyPayload)
        let legacyURL = dir.appendingPathComponent("backup-2026-01-01T00-00-00Z.json")
        try legacyData.write(to: legacyURL, options: .atomic)

        // Create an encrypted backup via writeBackup
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 2), amount: -20, category: "Transport")]
        _ = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 2))

        // listBackups should include both
        let backups = service.listBackups()
        #expect(backups.count == 2)
        #expect(backups.contains { $0.pathExtension == "json" })
        #expect(backups.contains { $0.pathExtension == "pftbackup" })
    }

    @Test func newestBackupPicksCorrectlyAmongMixedFiles() throws {
        let (storage, dir) = makeTempStorage()
        let service = makeService(storage: storage, maxBackupsKept: 10)

        // Create an older encrypted backup
        let tx = [TransactionSnapshot.test(timestamp: date(2026, 1, 1), amount: -10, category: "Food")]
        let olderEncrypted = try service.writeBackup(transactions: tx, recurrenceRules: [], now: date(2026, 1, 1, 9, 0))

        // Create a newer legacy .json backup
        let legacyPayload = BackupPayload(
            version: 1,
            createdAt: date(2026, 1, 2),
            transactions: [
                BackupTransaction(
                    timestamp: date(2026, 1, 2),
                    amount: -20,
                    note: "",
                    category: "Transport",
                    currencyCode: "EUR",
                    goalId: nil,
                    recurrenceRuleId: nil
                )
            ],
            recurrenceRules: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode(legacyPayload)
        let newerJson = dir.appendingPathComponent("backup-2026-01-02T09-00-00Z.json")
        try legacyData.write(to: newerJson, options: .atomic)

        // newestBackup should pick the newer one (regardless of format)
        let newest = service.newestBackup()
        #expect(newest == newerJson)
        #expect(newest != olderEncrypted)
    }
}
