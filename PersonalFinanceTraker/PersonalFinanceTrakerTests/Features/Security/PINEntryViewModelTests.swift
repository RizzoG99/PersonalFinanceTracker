import Testing
import Foundation

@testable import PersonalFinanceTraker

extension PINKeychainSerialTests {

@MainActor
@Suite(.serialized)
struct PINEntryViewModelTests {
    private let pinService = PINService()

    @Test("Correct PIN entered digit-by-digit unlocks the app")
    func correctPINUnlocks() async throws {
        await PINTestLock.shared.acquire()
        defer {
            try? pinService.clearPIN()
            Task { await PINTestLock.shared.release() }
        }

        try pinService.setPIN("1234")

        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        #expect(viewModel.isLockedOut == false)
        #expect(viewModel.errorMessage.isEmpty)

        viewModel.appendDigit("1")
        viewModel.appendDigit("2")
        viewModel.appendDigit("3")
        viewModel.appendDigit("4")

        #expect(viewModel.pinInput == "1234")

        // Success clears the input. Polled: a fixed 0.3s, then 1.0s, still raced the
        // 0.15s verify delay under full-suite load.
        #expect(await waitUntil { viewModel.pinInput.isEmpty })
        #expect(viewModel.errorMessage.isEmpty)
        #expect(viewModel.isLockedOut == false)
    }

    @Test("appendDigit no-ops while locked out")
    func appendDigitNoOpsWhileLockedOut() async throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        // Trigger 5 failures to lock out
        for _ in 0..<5 {
            _ = pinService.validatePINWithResult("0000")
        }

        #expect(pinService.lockoutDeadline != nil)

        // Manually set lockout on viewModel
        viewModel.isLockedOut = true

        // appendDigit should no-op
        viewModel.appendDigit("1")
        #expect(viewModel.pinInput.isEmpty)

        viewModel.appendDigit("2")
        #expect(viewModel.pinInput.isEmpty)
    }

    @Test("Lockout message displays when PIN entry results in lockout")
    func lockoutMessageDisplays() async throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        // Trigger 5 failures in pinService to lock out
        for _ in 0..<5 {
            _ = pinService.validatePINWithResult("0000")
        }

        #expect(pinService.lockoutDeadline != nil)

        // Now try to enter more digits on the locked-out viewModel
        // This should trigger verifyPIN with a locked-out result
        viewModel.appendDigit("5")
        viewModel.appendDigit("6")
        viewModel.appendDigit("7")
        viewModel.appendDigit("8")

        #expect(viewModel.pinInput == "5678")

        // Now locked out - check that lockoutMessage is populated
        #expect(await waitUntil { viewModel.isLockedOut })
        #expect(!viewModel.lockoutMessage.isEmpty)
        #expect(viewModel.lockoutMessage.contains("Locked out"))
        #expect(viewModel.errorMessage == viewModel.lockoutMessage)
    }

    @Test("Lockout UI is restored on a cold launch mid-lockout")
    func refreshLockoutStateRestoresLockoutAfterRelaunch() async throws {
        await PINTestLock.shared.acquire()
        defer {
            try? pinService.clearPIN()
            Task { await PINTestLock.shared.release() }
        }
        try? pinService.clearPIN()

        try pinService.setPIN("1234")

        for _ in 0..<5 {
            _ = pinService.validatePINWithResult("0000")
        }
        #expect(pinService.lockoutDeadline != nil)

        // A brand-new view model stands in for the one built on a fresh launch:
        // it has never seen a .lockedOut result, so its state starts clean.
        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)
        #expect(viewModel.isLockedOut == false)

        viewModel.refreshLockoutState()

        #expect(viewModel.isLockedOut)
        #expect(viewModel.lockoutMessage.contains("Locked out"))
        #expect(viewModel.errorMessage == viewModel.lockoutMessage)

        // And the pad stays inert without spending an attempt.
        viewModel.appendDigit("1")
        #expect(viewModel.pinInput.isEmpty)
    }

    @Test("refreshLockoutState leaves an unlocked view model alone")
    func refreshLockoutStateNoOpsWhenNotLockedOut() async throws {
        await PINTestLock.shared.acquire()
        defer {
            try? pinService.clearPIN()
            Task { await PINTestLock.shared.release() }
        }
        try? pinService.clearPIN()

        try pinService.setPIN("1234")

        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        viewModel.refreshLockoutState()

        #expect(viewModel.isLockedOut == false)
        #expect(viewModel.lockoutMessage.isEmpty)
        #expect(viewModel.errorMessage.isEmpty)
    }

    @Test("Incorrect PIN shows remaining attempts")
    func incorrectPINShowsRemainingAttempts() async throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        viewModel.appendDigit("5")
        viewModel.appendDigit("6")
        viewModel.appendDigit("7")
        viewModel.appendDigit("8")

        #expect(viewModel.pinInput == "5678")

        // A fixed 0.3s had to land inside a window: after the 0.15s verify, before the
        // 0.5s shake ends. Waiting for the message instead: the shake starts in the same call.
        #expect(await waitUntil { viewModel.errorMessage.contains("4 attempts") })
        #expect(viewModel.isShaking)

        // Reset fires after shake delay
        #expect(await waitUntil { viewModel.pinInput.isEmpty })
        #expect(viewModel.eyesOpen)
    }

    @Test("appendDigit does not append beyond 4 digits")
    func appendDigitBoundary() {
        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        viewModel.appendDigit("1")
        viewModel.appendDigit("2")
        viewModel.appendDigit("3")
        viewModel.appendDigit("4")
        viewModel.appendDigit("5")

        #expect(viewModel.pinInput == "1234")
        #expect(viewModel.pinInput.count == 4)
    }

    @Test("deleteDigit removes last digit and updates eyesOpen")
    func deleteDigit() {
        let authService = BiometricAuthService()
        let viewModel = PINEntryViewModel(pinService: pinService, authService: authService)

        viewModel.appendDigit("1")
        viewModel.appendDigit("2")
        viewModel.appendDigit("3")

        #expect(viewModel.pinInput == "123")
        #expect(!viewModel.eyesOpen)

        viewModel.deleteDigit()

        #expect(viewModel.pinInput == "12")
        #expect(!viewModel.eyesOpen)

        viewModel.deleteDigit()

        #expect(viewModel.pinInput == "1")
        #expect(!viewModel.eyesOpen)

        viewModel.deleteDigit()

        #expect(viewModel.pinInput.isEmpty)
        #expect(viewModel.eyesOpen)

        viewModel.deleteDigit()

        #expect(viewModel.pinInput.isEmpty)
        #expect(viewModel.eyesOpen)
    }
}

}
