import Foundation

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

    init(storage: BackupStorage = FileManagerBackupStorage(), maxBackupsKept: Int = 3) {
        self.storage = storage
        self.maxBackupsKept = maxBackupsKept
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
        let encryptedData = try BackupCrypto.seal(data)

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
                let decryptedData = try BackupCrypto.open(data)
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
