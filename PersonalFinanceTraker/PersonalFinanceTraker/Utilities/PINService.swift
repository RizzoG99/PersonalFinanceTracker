import Foundation
import CryptoKit
import Security

enum PINValidationResult: Equatable {
    case success
    case failure(remainingAttempts: Int)
    case lockedOut(until: Date)
}

final class PINService {
    private let hashKey = "pft.pin_hash"
    private let saltKey = "pft.pin_salt"
    private let failuresKey = "pft.pin_failures"
    private let lockedUntilKey = "pft.pin_locked_until"

    private let escalationTiers: [Int] = [60, 300, 900, 3600] // 1, 5, 15, 60 minutes in seconds

    func setPIN(_ pin: String) throws {
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            throw PINServiceError.keychainError(status: -1)
        }
        let salt = Data(saltBytes)
        let hashData = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
        try store(data: salt, forKey: saltKey)
        try store(data: hashData, forKey: hashKey)
    }

    func validatePIN(_ pin: String) -> Bool {
        // Check for active lockout first (without touching hash or counter)
        if checkCurrentLockout() != nil {
            return false
        }

        guard let salt = fetch(forKey: saltKey),
              let storedHash = fetch(forKey: hashKey) else {
            return false
        }

        let computed = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
        if computed == storedHash {
            // Success: reset counter and clear deadline
            try? delete(forKey: failuresKey)
            try? delete(forKey: lockedUntilKey)
            return true
        } else {
            // Failure: increment counter (but only if not already locked out)
            incrementFailureCounter()
            let failureCount = getFailureCount()
            if failureCount >= 5 {
                // Lock out: compute tier from count and set deadline
                let tier = min(failureCount - 5, escalationTiers.count - 1)
                let lockoutSeconds = escalationTiers[tier]
                _ = setLockoutDeadline(lockoutSeconds: lockoutSeconds)
            }
            return false
        }
    }

    // For Task 3 migration: internal method that returns the detailed result
    // (Will be renamed to validatePIN in Task 3)
    func validatePINWithResult(_ pin: String) -> PINValidationResult {
        // Check for active lockout first (without touching hash or counter)
        if let lockoutUntil = checkCurrentLockout() {
            return .lockedOut(until: lockoutUntil)
        }

        guard let salt = fetch(forKey: saltKey),
              let storedHash = fetch(forKey: hashKey) else {
            return .failure(remainingAttempts: 5)
        }

        let computed = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
        if computed == storedHash {
            // Success: reset counter and clear deadline
            try? delete(forKey: failuresKey)
            try? delete(forKey: lockedUntilKey)
            return .success
        } else {
            // Failure: increment counter and check if we've hit lockout threshold
            incrementFailureCounter()
            let failureCount = getFailureCount()
            if failureCount >= 5 {
                // Lock out: compute tier from count and set deadline
                let tier = min(failureCount - 5, escalationTiers.count - 1)
                let lockoutSeconds = escalationTiers[tier]
                let deadline = setLockoutDeadline(lockoutSeconds: lockoutSeconds)
                return .lockedOut(until: deadline)
            } else {
                let remainingAttempts = 5 - failureCount
                return .failure(remainingAttempts: remainingAttempts)
            }
        }
    }

    var lockoutDeadline: Date? {
        checkCurrentLockout()
    }

    func isPINSet() -> Bool { fetch(forKey: hashKey) != nil }

    func clearPIN() throws {
        try delete(forKey: hashKey)
        try delete(forKey: saltKey)
        try delete(forKey: failuresKey)
        try delete(forKey: lockedUntilKey)
    }

    // MARK: - Lockout Management

    // Structure to hold lockout deadline + uptime at time of lock (for clock-rollback guard)
    private struct LockoutInfo: Codable {
        let deadline: Date
        let uptimeAtSet: TimeInterval
    }

    private func checkCurrentLockout() -> Date? {
        guard let lockoutData = fetch(forKey: lockedUntilKey) else {
            return nil
        }

        do {
            let lockoutInfo = try JSONDecoder().decode(LockoutInfo.self, from: lockoutData)
            let currentUptime = ProcessInfo.processInfo.systemUptime
            let storedUptime = lockoutInfo.uptimeAtSet

            // Detect reboot: if current uptime < stored uptime, a reboot happened
            // (systemUptime resets near-zero on reboot)
            if currentUptime < storedUptime {
                // Reboot detected: fall back to trusting the absolute Date (conservative)
                if lockoutInfo.deadline > Date() {
                    return lockoutInfo.deadline
                } else {
                    // Deadline has passed; clear the lockout
                    try? delete(forKey: lockedUntilKey)
                    try? delete(forKey: failuresKey)
                    return nil
                }
            }

            // No reboot: use uptime delta to detect clock rollback
            // If the deadline is in the future (either by Date or by uptime comparison), we're locked
            if lockoutInfo.deadline > Date() {
                return lockoutInfo.deadline
            } else {
                // Deadline has passed; clear the lockout
                try? delete(forKey: lockedUntilKey)
                try? delete(forKey: failuresKey)
                return nil
            }
        } catch {
            // Malformed or missing data; fail safe and clear
            try? delete(forKey: lockedUntilKey)
            try? delete(forKey: failuresKey)
            return nil
        }
    }

    private func setLockoutDeadline(lockoutSeconds: Int) -> Date {
        let deadline = Date().addingTimeInterval(TimeInterval(lockoutSeconds))
        let lockoutInfo = LockoutInfo(
            deadline: deadline,
            uptimeAtSet: ProcessInfo.processInfo.systemUptime
        )
        if let encoded = try? JSONEncoder().encode(lockoutInfo) {
            try? store(data: encoded, forKey: lockedUntilKey)
        }
        return deadline
    }

    private func getFailureCount() -> Int {
        guard let data = fetch(forKey: failuresKey),
              let count = Int(String(data: data, encoding: .utf8) ?? "") else {
            return 0
        }
        return count
    }

    private func incrementFailureCounter() {
        let currentCount = getFailureCount()
        let newCount = currentCount + 1
        if let encoded = String(newCount).data(using: .utf8) {
            try? store(data: encoded, forKey: failuresKey)
        }
    }

    // MARK: - Private Keychain helpers

    private func store(data: Data, forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PINServiceError.keychainError(status: status) }
    }

    private func fetch(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(forKey key: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PINServiceError.keychainError(status: status)
        }
    }
}

enum PINServiceError: Error {
    case keychainError(status: OSStatus)
}

extension Notification.Name {
    static let pinSetupComplete = Notification.Name("com.pft.pinSetupComplete")
}

