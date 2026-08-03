import Foundation

final class BackupService {
    enum BackupError: Error, Equatable {
        case iCloudUnavailable
        case emptyStore
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
            version: 1,
            createdAt: now,
            transactions: BackupMapper.makeTransactions(from: transactions),
            recurrenceRules: BackupMapper.makeRecurrenceRules(from: recurrenceRules)
        )
        let data = try Self.encoder.encode(payload)
        let fileURL = containerURL.appendingPathComponent(Self.filename(for: now))
        try data.write(to: fileURL, options: .atomic)

        pruneOldBackups(in: containerURL)
        return fileURL
    }

    func listBackups() -> [URL] {
        guard let containerURL = storage.containerURL() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)) ?? []
        // Filenames are ISO-8601-based, so lexicographic descending order is also newest-first.
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func newestBackup() -> URL? {
        listBackups().first
    }

    func readBackup(at url: URL) throws -> BackupPayload {
        let data = try Data(contentsOf: url)
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
        return "backup-\(safe).json"
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
