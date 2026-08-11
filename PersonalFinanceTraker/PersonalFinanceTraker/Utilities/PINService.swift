import Foundation
import CryptoKit
import Security
import CommonCrypto

enum PINValidationResult: Equatable {
    case success
    case failure(remainingAttempts: Int)
    case lockedOut(until: Date)
}

final class PINService {
    private let hashKey = "pft.pin_hash"
    private let saltKey = "pft.pin_salt"
    private let versionKey = "pft.pin_hash_version"
    private let failuresKey = "pft.pin_failures"
    private let lockedUntilKey = "pft.pin_locked_until"

    private let escalationTiers: [Int] = [60, 300, 900, 3600] // 1, 5, 15, 60 minutes in seconds
    private let pbkdf2Rounds: UInt32 = 210_000
    private let derivedKeyLength: Int = 32

    func setPIN(_ pin: String) throws {
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            throw PINServiceError.keychainError(status: -1)
        }
        let salt = Data(saltBytes)
        let hashData = derivePBKDF2(pin: pin, salt: salt)
        try store(data: salt, forKey: saltKey)
        try store(data: hashData, forKey: hashKey)
        try store(data: "2".data(using: .utf8)!, forKey: versionKey)
    }

    func validatePIN(_ pin: String) -> Bool {
        let result = validatePINWithResult(pin)
        return result == .success
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

        let versionData = fetch(forKey: versionKey)
        let versionString = versionData.flatMap { String(data: $0, encoding: .utf8) }
        let isLegacy = versionString != "2"

        let isValid: Bool
        if isLegacy {
            // ponytail: legacy SHA-256 verification, beta-only. DELETE before App Store
            // release — drop this branch, drop `pft.pin_hash_version`, and have setPIN/
            // validatePIN speak PBKDF2 only. Any straggler on the old format just
            // re-runs PIN setup.
            let computed = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
            isValid = constantTimeEqual(computed, storedHash)
        } else {
            let computed = derivePBKDF2(pin: pin, salt: salt)
            isValid = constantTimeEqual(computed, storedHash)
        }

        if isValid {
            // Success: reset counter and clear deadline
            try? delete(forKey: failuresKey)
            try? delete(forKey: lockedUntilKey)

            // Lazy migration: if version was legacy, upgrade to PBKDF2
            if isLegacy {
                let pbkdf2Hash = derivePBKDF2(pin: pin, salt: salt)
                try? store(data: pbkdf2Hash, forKey: hashKey)
                try? store(data: "2".data(using: .utf8)!, forKey: versionKey)
            }

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
        try delete(forKey: versionKey)
        try delete(forKey: failuresKey)
        try delete(forKey: lockedUntilKey)
    }

    // MARK: - PBKDF2 Derivation and Comparison

    private func derivePBKDF2(pin: String, salt: Data) -> Data {
        guard let pinBytes = pin.data(using: .utf8) else {
            return Data()
        }

        var derivedKey = [UInt8](repeating: 0, count: derivedKeyLength)
        let saltBytes = [UInt8](salt)

        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            (pin as NSString).utf8String, pinBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCHmacAlgSHA256),
            pbkdf2Rounds,
            &derivedKey,
            derivedKey.count
        )

        guard status == kCCSuccess else {
            return Data()
        }

        return Data(derivedKey)
    }

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else {
            return false
        }

        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[i] ^ b[i]
        }

        return result == 0
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

            // ponytail: reboot detection only; does not catch active clock rollback.
            // Ceiling: detects systemUptime reset (genuine reboot) but not device clock
            // set backward during runtime. Upgrade path: compare stored uptime delta
            // (deadline - uptimeAtSet) with current (now - currentUptime) to catch
            // mid-runtime rollbacks.

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

            // No reboot: Date comparison alone; assumes device clock doesn't roll backward
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
        do {
            let encoded = try JSONEncoder().encode(lockoutInfo)
            try store(data: encoded, forKey: lockedUntilKey)
        } catch {
            // Encoding/storing lockout should not fail in normal operation.
            // If it does, fail-safe: lockout deadline is forgotten on next app launch.
            // Assert in debug to catch unexpected failures during development.
            assertionFailure("Failed to persist lockout deadline: \(error)")
        }
        return deadline
    }

    private func getFailureCount() -> Int {
        // ponytail: counter stored as UTF-8 string, not Codable struct.
        // Ceiling: works for 0-8 attempts; upgrade path is Codable for type-safety
        // and schema versioning if counter logic becomes more complex.
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

    // MARK: - Test Helpers (internal for @testable)

    func storeTestData(_ data: Data, forKey key: String) throws {
        try store(data: data, forKey: key)
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

