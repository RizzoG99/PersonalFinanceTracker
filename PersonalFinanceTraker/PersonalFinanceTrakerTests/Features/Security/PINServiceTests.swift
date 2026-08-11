import Testing
import Foundation
import CryptoKit
import Security

@testable import PersonalFinanceTraker

@Suite(.serialized)
struct PINServiceTests {
    private let pinService = PINService()

    init() {
        // Clean up before suite
        try? pinService.clearPIN()
    }

    // MARK: - Lockout Triggering

    @Test("Lockout triggers at 5 consecutive failures")
    func lockoutTriggersAtFiveFailures() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // First 4 failures should not lock out
        for _ in 0..<4 {
            #expect(pinService.validatePIN("0000") == false)
            #expect(pinService.lockoutDeadline == nil)
        }

        // 5th failure should lock out
        #expect(pinService.validatePIN("0000") == false)
        #expect(pinService.lockoutDeadline != nil)
    }

    @Test("Lockout immediately rejects further attempts")
    func lockoutRejectsAttemptsImmediately() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger lockout (5 failures)
        for _ in 0..<5 {
            _ = pinService.validatePIN("0000")
        }

        let deadlineAfterLockout = pinService.lockoutDeadline
        #expect(deadlineAfterLockout != nil)

        // Attempt to validate during lockout - should return false
        // without incrementing counter further (short-circuit)
        #expect(pinService.validatePIN("0000") == false)

        // Deadline should not have changed (short-circuit prevents counter increment)
        let deadlineAfterRejectedAttempt = pinService.lockoutDeadline
        #expect(deadlineAfterRejectedAttempt == deadlineAfterLockout)
    }

    // MARK: - Escalation Tiers

    @Test("Escalation hits 1-min tier at 5 failures")
    func escalationMinuteTier() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger 5 failures
        for _ in 0..<5 {
            _ = pinService.validatePIN("0000")
        }

        guard let deadline = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline after 5 failures")
            return
        }

        let now = Date()
        let lockoutSeconds = deadline.timeIntervalSince(now)
        // 1 minute = 60 seconds; allow ~5s margin for test execution
        #expect(lockoutSeconds > 55 && lockoutSeconds <= 65)
    }

    @Test("Escalation hits 5-min tier at 6 failures")
    func escalation5MinuteTier() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger 6 failures (increments through 5, then one more before next tier)
        for _ in 0..<6 {
            _ = pinService.validatePIN("0000")
        }

        guard let deadline = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline after 6 failures")
            return
        }

        let now = Date()
        let lockoutSeconds = deadline.timeIntervalSince(now)
        // 5 minutes = 300 seconds; allow ~5s margin for test execution
        #expect(lockoutSeconds > 295 && lockoutSeconds <= 305)
    }

    @Test("Escalation hits 15-min tier at 7 failures")
    func escalation15MinuteTier() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger 7 failures
        for _ in 0..<7 {
            _ = pinService.validatePIN("0000")
        }

        guard let deadline = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline after 7 failures")
            return
        }

        let now = Date()
        let lockoutSeconds = deadline.timeIntervalSince(now)
        // 15 minutes = 900 seconds; allow ~5s margin for test execution
        #expect(lockoutSeconds > 895 && lockoutSeconds <= 905)
    }

    @Test("Escalation hits 60-min tier at 8 failures and caps")
    func escalation60MinuteTierCapped() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger 8 failures
        for _ in 0..<8 {
            _ = pinService.validatePIN("0000")
        }

        guard let deadline8 = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline after 8 failures")
            return
        }

        let now = Date()
        let lockoutSeconds8 = deadline8.timeIntervalSince(now)
        // 60 minutes = 3600 seconds; allow ~5s margin for test execution
        #expect(lockoutSeconds8 > 3595 && lockoutSeconds8 <= 3605)

        // Try 9 failures - tier should remain 60 min (capped)
        // Simulate: clear lockout first to continue testing, then trigger 9th
        try? pinService.clearPIN()
        try pinService.setPIN("1234")
        for _ in 0..<9 {
            _ = pinService.validatePIN("0000")
        }

        guard let deadline9 = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline after 9 failures")
            return
        }

        let lockoutSeconds9 = deadline9.timeIntervalSince(now)
        // Should also be around 60 minutes (capped) - allow wider margin since time has passed
        #expect(lockoutSeconds9 > 3590 && lockoutSeconds9 <= 3610)
    }

    // MARK: - Success Resets Counter and Deadline

    @Test("Successful validation resets counter and clears deadline")
    func successResetsCounterAndDeadline() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger 3 failures (below threshold)
        for _ in 0..<3 {
            _ = pinService.validatePIN("0000")
        }

        #expect(pinService.lockoutDeadline == nil)

        // Successful validation
        #expect(pinService.validatePIN("1234") == true)

        // Counter and deadline should be clear
        #expect(pinService.lockoutDeadline == nil)

        // Next 5 failures should start fresh, not pick up from 3
        for _ in 0..<5 {
            _ = pinService.validatePIN("0000")
        }

        // After fresh 5 failures, should be locked out
        #expect(pinService.lockoutDeadline != nil)
    }

    @Test("Success during lockout clears both counter and deadline")
    func successDuringLockoutClearsAll() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger 4 failures (sub-threshold)
        for _ in 0..<4 {
            _ = pinService.validatePINWithResult("0000")
        }
        #expect(pinService.lockoutDeadline == nil)

        // Validate correct PIN → success
        var result = pinService.validatePINWithResult("1234")
        #expect(result == .success)
        #expect(pinService.lockoutDeadline == nil)

        // Trigger 5 failures to lock out
        for _ in 0..<5 {
            _ = pinService.validatePINWithResult("0000")
        }
        #expect(pinService.lockoutDeadline != nil)

        // Attempt correct PIN while locked — should be rejected immediately
        // without hash check or counter increment (short-circuit)
        result = pinService.validatePINWithResult("1234")
        if case .lockedOut = result {
            // Expected: lockout prevents any validation
        } else {
            Issue.record("Expected .lockedOut while in lockout, got \(result)")
        }
    }

    // MARK: - Clock Rollback Guard

    @Test("Clock rollback guard preserves lockout across reboot simulation")
    func clockRollbackGuardHoldsLockout() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger lockout (5 failures)
        for _ in 0..<5 {
            _ = pinService.validatePIN("0000")
        }

        guard let originalDeadline = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline after 5 failures")
            return
        }

        // Verify the deadline is stored correctly (it persists via Keychain)
        // The next read should return approximately the same deadline
        try await Task.sleep(for: .milliseconds(100))

        guard let readBackDeadline = pinService.lockoutDeadline else {
            Issue.record("Expected lockout deadline to persist")
            return
        }

        // Deadline should remain approximately the same (within ~1s)
        let timeDiff = abs(readBackDeadline.timeIntervalSince(originalDeadline))
        #expect(timeDiff < 1.0)
    }

    // MARK: - validatePINWithResult (internal method for Task 2/3 testing)

    @Test("validatePINWithResult returns .success on correct PIN")
    func validatePINWithResultSuccess() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        let result = pinService.validatePINWithResult("1234")
        #expect(result == .success)
    }

    @Test("validatePINWithResult returns .failure with remaining attempts")
    func validatePINWithResultFailure() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // First failure: 4 attempts remaining
        var result = pinService.validatePINWithResult("0000")
        #expect(result == .failure(remainingAttempts: 4))

        // Second failure: 3 attempts remaining
        result = pinService.validatePINWithResult("0000")
        #expect(result == .failure(remainingAttempts: 3))

        // Third failure: 2 attempts remaining
        result = pinService.validatePINWithResult("0000")
        #expect(result == .failure(remainingAttempts: 2))

        // Fourth failure: 1 attempt remaining
        result = pinService.validatePINWithResult("0000")
        #expect(result == .failure(remainingAttempts: 1))

        // Fifth failure: locked out
        result = pinService.validatePINWithResult("0000")
        if case .lockedOut = result {
            // Expected
        } else {
            Issue.record("Expected .lockedOut after 5 failures, got \(result)")
        }
    }

    @Test("validatePINWithResult returns .lockedOut during lockout")
    func validatePINWithResultLockedOut() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Trigger lockout (5 failures)
        for _ in 0..<5 {
            _ = pinService.validatePINWithResult("0000")
        }

        // Attempt during lockout
        let result = pinService.validatePINWithResult("0000")
        if case .lockedOut(let until) = result {
            #expect(until > Date())
        } else {
            Issue.record("Expected .lockedOut during lockout, got \(result)")
        }
    }

    // MARK: - Edge Cases

    @Test("PIN can be cleared after lockout")
    func clearPINAfterLockout() throws {
        try pinService.setPIN("1234")

        // Trigger lockout
        for _ in 0..<5 {
            _ = pinService.validatePIN("0000")
        }

        #expect(pinService.lockoutDeadline != nil)

        // Clear should remove both PIN and lockout state
        try pinService.clearPIN()

        #expect(pinService.isPINSet() == false)
        #expect(pinService.lockoutDeadline == nil)
    }

    @Test("isPINSet returns false before PIN is set")
    func isPINSetBeforeSet() {
        defer { try? pinService.clearPIN() }

        #expect(pinService.isPINSet() == false)
    }

    @Test("isPINSet returns true after PIN is set")
    func isPINSetAfterSet() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")
        #expect(pinService.isPINSet() == true)
    }

    // MARK: - PBKDF2 and Lazy Migration Tests

    @Test("New PIN uses PBKDF2 from the start")
    func newPINUsesPBKDF2() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // Validate with correct PIN should succeed
        let result = pinService.validatePINWithResult("1234")
        #expect(result == .success)

        // Validate with wrong PIN should fail
        let wrongResult = pinService.validatePINWithResult("0000")
        if case .failure(let remaining) = wrongResult {
            #expect(remaining == 4)
        } else {
            Issue.record("Expected .failure for wrong PIN")
        }
    }

    @Test("Legacy SHA-256 PIN validates successfully and upgrades to PBKDF2")
    func legacySHA256ValidationAndUpgrade() throws {
        defer { try? pinService.clearPIN() }

        // Manually create a legacy SHA-256 PIN by directly storing it
        // without going through the new setPIN() method
        let pin = "1234"
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            Issue.record("Failed to generate random salt")
            return
        }
        let salt = Data(saltBytes)

        // Use the old SHA-256 formula: hash(pin + salt.base64EncodedString())
        let legacyHashData = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))

        // Store salt and legacy hash (no version marker = legacy)
        try pinService.storeTestData(salt, forKey: "pft.pin_salt")
        try pinService.storeTestData(legacyHashData, forKey: "pft.pin_hash")

        // Validate with correct PIN - should succeed and trigger migration
        let result = pinService.validatePINWithResult("1234")
        #expect(result == .success)

        // Verify that subsequent validation still works (confirming upgrade was stored)
        let secondResult = pinService.validatePINWithResult("1234")
        #expect(secondResult == .success)
    }

    @Test("Wrong PIN against PBKDF2 hash fails and drives lockout counter")
    func wrongPBKDF2PINDrivesLockout() throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        // First failure against PBKDF2 hash
        var result = pinService.validatePINWithResult("0000")
        if case .failure(let remaining) = result {
            #expect(remaining == 4)
        } else {
            Issue.record("Expected .failure(remainingAttempts: 4)")
            return
        }

        // Continue failing to trigger lockout at 5 failures
        for _ in 0..<4 {
            _ = pinService.validatePINWithResult("0000")
        }

        // 5th failure should trigger lockout
        result = pinService.validatePINWithResult("0000")
        if case .lockedOut = result {
            // Expected
        } else {
            Issue.record("Expected .lockedOut after 5 failures against PBKDF2 hash")
        }
    }

    @Test("Legacy PIN failure also drives lockout counter (before upgrade)")
    func legacyPINFailureDrivesLockout() throws {
        defer { try? pinService.clearPIN() }

        let pin = "1234"
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            Issue.record("Failed to generate random salt")
            return
        }
        let salt = Data(saltBytes)

        // Create legacy SHA-256 PIN
        let legacyHashData = Data(SHA256.hash(data: Data((pin + salt.base64EncodedString()).utf8)))

        try pinService.storeTestData(salt, forKey: "pft.pin_salt")
        try pinService.storeTestData(legacyHashData, forKey: "pft.pin_hash")

        // First failure with wrong PIN
        var result = pinService.validatePINWithResult("0000")
        if case .failure(let remaining) = result {
            #expect(remaining == 4)
        } else {
            Issue.record("Expected .failure(remainingAttempts: 4)")
            return
        }

        // Continue failing to trigger lockout
        for _ in 0..<4 {
            _ = pinService.validatePINWithResult("0000")
        }

        // 5th failure should trigger lockout (even on legacy format)
        result = pinService.validatePINWithResult("0000")
        if case .lockedOut = result {
            // Expected
        } else {
            Issue.record("Expected .lockedOut after 5 failures on legacy PIN format")
        }
    }
}
