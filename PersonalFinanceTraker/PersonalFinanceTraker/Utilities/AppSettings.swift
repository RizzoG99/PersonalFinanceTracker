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

    /// Share of this cycle's income Safe to Spend keeps back for the unexpected (#190).
    var safeToSpendBufferPercent: Int {
        didSet {
            guard Self.bufferRange.contains(safeToSpendBufferPercent) else {
                safeToSpendBufferPercent = max(Self.bufferRange.lowerBound, min(Self.bufferRange.upperBound, safeToSpendBufferPercent))
                return
            }
            UserDefaults.standard.set(safeToSpendBufferPercent, forKey: "safeToSpendBufferPercent")
        }
    }

    static let bufferRange = 0...20

    var lastBackupDate: Date? {
        didSet {
            UserDefaults.standard.set(lastBackupDate, forKey: "lastBackupDate")
        }
    }

    init() {
        let v = UserDefaults.standard.integer(forKey: "payCycleStartDay")
        payCycleStartDay = v == 0 ? 1 : v
        safeToSpendBufferPercent = Self.storedBufferPercent
        lastBackupDate = UserDefaults.standard.object(forKey: "lastBackupDate") as? Date
    }

    static var storedStartDay: Int {
        let v = UserDefaults.standard.integer(forKey: "payCycleStartDay")
        return v == 0 ? 1 : v
    }

    /// 5% until the user picks a value — 0 is a valid choice, so a missing key isn't 0.
    static var storedBufferPercent: Int {
        UserDefaults.standard.object(forKey: "safeToSpendBufferPercent") as? Int ?? 5
    }
}
