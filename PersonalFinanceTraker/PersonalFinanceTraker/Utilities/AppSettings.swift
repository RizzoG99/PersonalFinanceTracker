import Foundation
import UIKit

@Observable @MainActor
final class AppSettings: BackupSchedulingSettings {
    /// Privacy blur toggle (shake-to-hide). Intentionally not persisted — always starts
    /// revealed on launch; this is a quick temporary hide, not a saved preference.
    var hideAmounts = false

    /// Single entry point for flipping privacy mode, whether triggered by a shake or the
    /// eye-icon toggle — keeps the haptic feedback in one place instead of duplicated at
    /// each call site.
    func toggleHideAmounts() {
        hideAmounts.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    var payCycleStartDay: Int {
        didSet {
            guard (1...28).contains(payCycleStartDay) else {
                payCycleStartDay = max(1, min(28, payCycleStartDay))
                return
            }
            UserDefaults.standard.set(payCycleStartDay, forKey: "payCycleStartDay")
        }
    }

    var lastBackupDate: Date? {
        didSet {
            UserDefaults.standard.set(lastBackupDate, forKey: "lastBackupDate")
        }
    }

    init() {
        let v = UserDefaults.standard.integer(forKey: "payCycleStartDay")
        payCycleStartDay = v == 0 ? 1 : v
        lastBackupDate = UserDefaults.standard.object(forKey: "lastBackupDate") as? Date
    }

    static var storedStartDay: Int {
        let v = UserDefaults.standard.integer(forKey: "payCycleStartDay")
        return v == 0 ? 1 : v
    }
}
