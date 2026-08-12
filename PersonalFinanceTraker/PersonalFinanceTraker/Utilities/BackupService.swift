import Foundation
import CryptoKit

final class BackupService {
    enum BackupError: Error, Equatable {
        case iCloudUnavailable
        case emptyStore
        case decryptionFailed
        case sealingFailed
        case keychainError
    }

    private let storage: BackupStorage
    private let maxBackupsKept: Int
    private let keyProvider: () throws -> SymmetricKey

    // ponytail: keyProvider defaults to the real (Keychain-backed, iCloud-synced) key
    // so production is unchanged. Tests inject a single fixed in-memory key per
    // BackupService instance instead — BackupCrypto.key()'s Keychain account is
    // process-global, so two BackupServiceTests/RestoreServiceTests running
    // concurrently (Swift Testing parallelizes by default) raced on it: both saw "no
    // key yet", both minted their own, and whichever SecItemAdd lost decrypted with a
    // key that was no longer what the other test had just overwritten. Passed
    // locally where less true parallelism happened to hide it; failed reliably on
    // Xcode Cloud's build. Injecting the key sidesteps shared Keychain state
    // entirely rather than papering over it with serialization.
    init(
        storage: BackupStorage = FileManagerBackupStorage(),
        maxBackupsKept: Int = 3,
        keyProvider: @escaping () throws -> SymmetricKey = BackupCrypto.key
    ) {
        self.storage = storage
        self.maxBackupsKept = maxBackupsKept
        self.keyProvider = keyProvider
    }

    @discardableResult
    func writeBackup(transactions: [TransactionSnapshot], recurrenceRules: [RecurrenceRuleSnapshot], now: Date = Date()) throws -> URL {
        guard !transactions.isEmpty else { throw BackupError.emptyStore }
        guard let containerURL = storage.containerURL() else { throw BackupError.iCloudUnavailable }

        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let payload = BackupPayload(
            version: 2,
            createdAt: now,
            transactions: BackupMapper.makeTransactions(from: transactions),
            recurrenceRules: BackupMapper.makeRecurrenceRules(from: recurrenceRules)
        )
        let data = try Self.encoder.encode(payload)

        // Encrypt the payload
        let key = try keyProvider()
        let encryptedData = try BackupCrypto.seal(data, using: key)

        let fileURL = containerURL.appendingPathComponent(Self.filename(for: now))
        try encryptedData.write(to: fileURL, options: .atomic)

        // Set file protection to complete
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )

        pruneOldBackups(in: containerURL)
        return fileURL
    }

    func listBackups() -> [URL] {
        guard let containerURL = storage.containerURL() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)) ?? []
        // Accept both .json (legacy) and .pftbackup (encrypted) files.
        // Filenames are ISO-8601-based, so lexicographic descending order is also newest-first.
        return files
            .filter { $0.pathExtension == "json" || $0.pathExtension == "pftbackup" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func newestBackup() -> URL? {
        listBackups().first
    }

    func readBackup(at url: URL) throws -> BackupPayload {
        let data = try Data(contentsOf: url)

        // Try to decrypt if it's an encrypted backup (.pftbackup extension)
        if url.pathExtension == "pftbackup" {
            do {
                let key = try keyProvider()
                let decryptedData = try BackupCrypto.open(data, using: key)
                let payload = try Self.decoder.decode(BackupPayload.self, from: decryptedData)
                // Validate version for encrypted backups
                guard payload.version >= 2 else {
                    throw BackupError.decryptionFailed
                }
                return payload
            } catch BackupError.decryptionFailed {
                // Re-throw decryption failures with the specific error
                throw BackupError.decryptionFailed
            } catch {
                // If decoding fails after successful decryption, it's a data corruption issue
                throw error
            }
        }

        // Legacy plaintext JSON backup (.json extension) — decode directly
        return try Self.decoder.decode(BackupPayload.self, from: data)
    }

    private func pruneOldBackups(in containerURL: URL) {
        let backups = listBackups()
        guard backups.count > maxBackupsKept else { return }
        for url in backups.dropFirst(maxBackupsKept) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func filename(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let safe = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "backup-\(safe).pftbackup"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
