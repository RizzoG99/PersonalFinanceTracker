import Foundation
@testable import PersonalFinanceTraker

struct TestBackupStorage: BackupStorage {
    let url: URL?
    func containerURL() -> URL? { url }
}
