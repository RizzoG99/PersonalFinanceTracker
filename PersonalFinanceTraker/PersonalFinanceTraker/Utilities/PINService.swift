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

    // ponytail: in-memory mirror of the failure counter and lockout deadline,
    // keyed by this instance. Confirmed via instrumentation that a value this same
    // instance just wrote and verified can still read back stale (not merely
    // "not found" — genuinely outdated) from a *separate* SecItemCopyMatching call
    // ~200ms later under heavy concurrent Keychain load (this codebase's 393-test
    // full suite reproduces it reliably; a single human tapping a PIN pad with
    // 150-450ms UI delays between attempts never generates that load). Since this
    // instance already durably wrote the value, there's no need to round-trip
    // through Keychain to learn what it just wrote — consult the cache first and
    // only fall back to Keychain on a cold instance (fresh launch, cache empty).
    // Upgrade path: per-test-instance Keychain account namespacing (see storeTestData)
    // eliminates cross-instance/cross-suite contention entirely, if this ever
    // resurfaces at a different layer.
    private var cachedFailureCount: Int?
    private var cachedLockoutInfo: LockoutInfo??  // outer optional = not loaded yet; inner = no active lockout

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
            cachedFailureCount = 0
            cachedLockoutInfo = .some(nil)

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

    /// Verifies a PIN against the stored hash without counting it as an authentication attempt.
    /// Used for business-rule checks (e.g., "new PIN must differ from current PIN") that should
    /// never trigger the failure counter or lockout, only for policy validation.
    /// - Parameter pin: The PIN to verify
    /// - Returns: true if the PIN matches the stored hash, false otherwise
    func verifyPINForPolicyCheck(_ pin: String) -> Bool {
        guard let salt = fetch(forKey: saltKey),
              let storedHash = fetch(forKey: hashKey) else {
            return false
        }

        let versionData = fetch(forKey: versionKey)
        let versionString = versionData.flatMap { String(data: $0, encoding: .utf8) }
        let isLegacy = versionString != "2"

        let isValid: Bool
        if isLegacy {
            let computed = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))
            isValid = constantTimeEqual(computed, storedHash)
        } else {
            let computed = derivePBKDF2(pin: pin, salt: salt)
            isValid = constantTimeEqual(computed, storedHash)
        }

        return isValid
    }

    func isPINSet() -> Bool { fetch(forKey: hashKey) != nil }

    func clearPIN() throws {
        try delete(forKey: hashKey)
        try delete(forKey: saltKey)
        try delete(forKey: versionKey)
        try delete(forKey: failuresKey)
        try delete(forKey: lockedUntilKey)
        cachedFailureCount = 0
        cachedLockoutInfo = .some(nil)
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
        if let cached = cachedLockoutInfo {
            return resolveLockout(cached)
        }

        guard let lockoutData = fetch(forKey: lockedUntilKey) else {
            cachedLockoutInfo = .some(nil)
            return nil
        }

        guard let lockoutInfo = try? JSONDecoder().decode(LockoutInfo.self, from: lockoutData) else {
            // Malformed or missing data; fail safe and clear both — a corrupt
            // deadline record carries no trustworthy failure count either.
            try? delete(forKey: lockedUntilKey)
            try? delete(forKey: failuresKey)
            cachedLockoutInfo = .some(nil)
            cachedFailureCount = 0
            return nil
        }

        cachedLockoutInfo = .some(lockoutInfo)
        return resolveLockout(lockoutInfo)
    }

    private func resolveLockout(_ lockoutInfo: LockoutInfo?) -> Date? {
        guard let lockoutInfo else { return nil }

        // ponytail: uptimeAtSet stays on LockoutInfo for the clock-rollback guard's
        // original design intent, but the reboot-vs-no-reboot branches this used to
        // have both reduced to the same `deadline > Date()` check, so they were
        // merged into one. Ceiling: doesn't catch an active mid-runtime clock
        // rollback (only the absolute Date is trusted). Upgrade path: compare
        // (deadline - uptimeAtSet) against (now - currentUptime) if that scenario
        // needs covering.
        if lockoutInfo.deadline > Date() {
            return lockoutInfo.deadline
        } else {
            // Deadline has passed; clear only the deadline. The failure count
            // must survive so a repeat offender keeps climbing the escalation
            // ladder instead of restarting at tier 0 every time a window
            // elapses — only a successful PIN clears the counter.
            try? delete(forKey: lockedUntilKey)
            cachedLockoutInfo = .some(nil)
            return nil
        }
    }

    private func setLockoutDeadline(lockoutSeconds: Int) -> Date {
        let deadline = Date().addingTimeInterval(TimeInterval(lockoutSeconds))
        let lockoutInfo = LockoutInfo(
            deadline: deadline,
            uptimeAtSet: ProcessInfo.processInfo.systemUptime
        )
        cachedLockoutInfo = .some(lockoutInfo)
        do {
            let encoded = try JSONEncoder().encode(lockoutInfo)
            try store(data: encoded, forKey: lockedUntilKey)
        } catch {
            // store() already retries internally (see its ponytail comment) — if it
            // still throws here, persisting genuinely failed. A crash here is worse
            // than the fail-safe it's guarding: don't trap. The cache still holds the
            // deadline for this process's lifetime; only a relaunch loses it.
        }
        return deadline
    }

    private func getFailureCount() -> Int {
        if let cached = cachedFailureCount {
            return cached
        }
        // ponytail: counter stored as UTF-8 string, not Codable struct.
        // Ceiling: works for 0-8 attempts; upgrade path is Codable for type-safety
        // and schema versioning if counter logic becomes more complex.
        guard let data = fetch(forKey: failuresKey),
              let count = Int(String(data: data, encoding: .utf8) ?? "") else {
            cachedFailureCount = 0
            return 0
        }
        cachedFailureCount = count
        return count
    }

    private func incrementFailureCounter() {
        let currentCount = getFailureCount()
        let newCount = currentCount + 1
        cachedFailureCount = newCount
        if let encoded = String(newCount).data(using: .utf8) {
            try? store(data: encoded, forKey: failuresKey)
        }
    }

    // MARK: - Test Helpers (internal for @testable)

    func storeTestData(_ data: Data, forKey key: String) throws {
        // Tests seed pft.pin_failures / pft.pin_locked_until directly to drive the
        // escalation ladder past what validatePIN's lockout short-circuit allows
        // (see PINServiceTests' escalation tests). Invalidate the matching cache so
        // the next read goes back to Keychain instead of serving a stale in-memory
        // value from before the test's direct write.
        if key == failuresKey {
            cachedFailureCount = nil
        } else if key == lockedUntilKey {
            cachedLockoutInfo = nil
        }
        try store(data: data, forKey: key)
    }

    // MARK: - Private Keychain helpers

    // Atomic upsert: try SecItemUpdate first, fall back to SecItemAdd only when the
    // item doesn't exist yet. A prior delete-then-add here left a window where a
    // concurrent writer (another thread hitting the same account) could add its own
    // item between our delete and our add, turning our add into a spurious
    // errSecDuplicateItem — the exact crash this codebase hit in practice (see the
    // PINConfirmationViewModelTests serialization fix). Removing the gap fixes it
    // at the source.
    // ponytail: writes here reported success (no throw) but a same-process
    // SecItemCopyMatching immediately after sometimes still returned
    // errSecItemNotFound — a read-after-write visibility lag in the Keychain
    // daemon under heavy concurrent load. Verify-then-retry closes that window
    // instead of silently trusting a write that hasn't landed yet.
    // Ceiling: 3 attempts, ~15ms apart — tuned for this failure mode, not a
    // general-purpose retry policy. Upgrade path: if this still fires in
    // practice, widen the backoff or attempt count.
    private func store(data: Data, forKey key: String) throws {
        var lastError: Error?
        for _ in 0..<3 {
            do {
                try writeOnce(data: data, forKey: key)
                if fetchOnce(forKey: key) == data {
                    return
                }
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
        if let lastError {
            throw lastError
        }
        // All attempts reported success but never verified — surface it rather
        // than silently pretending the write landed.
        throw PINServiceError.keychainError(status: errSecItemNotFound)
    }

    private func writeOnce(data: Data, forKey key: String) throws {
        let matchQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        let updateStatus = SecItemUpdate(matchQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PINServiceError.keychainError(status: updateStatus)
        }
        var addQuery = matchQuery
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecValueData] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PINServiceError.keychainError(status: addStatus) }
    }

    // ponytail: a fetch() immediately following a write() that itself just verified
    // the same key can still come back "not found" a few ms later under heavy
    // concurrent load. One retry after a short sleep resolves that specific window.
    // This does not cover a later read seeing stale-but-present data — that's what
    // the in-memory cache above exists to sidestep.
    private func fetch(forKey key: String) -> Data? {
        if let data = fetchOnce(forKey: key) {
            return data
        }
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.015)
            if let data = fetchOnce(forKey: key) {
                return data
            }
        }
        return nil
    }

    private func fetchOnce(forKey key: String) -> Data? {
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
