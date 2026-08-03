import Foundation

protocol BackupStorage: Sendable {
    /// Returns the directory backups should be written into, or nil if unavailable (e.g. no iCloud account).
    func containerURL() -> URL?
}

struct FileManagerBackupStorage: BackupStorage {
    func containerURL() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return base.appendingPathComponent("Documents", isDirectory: true)
    }
}
