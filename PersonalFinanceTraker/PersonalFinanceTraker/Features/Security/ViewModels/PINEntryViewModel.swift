import SwiftUI
import LocalAuthentication

// ponytail: `nonisolated` is rejected on any *mutable* stored property, only on `let` —
// this box's single field of indirection turns the storage immutable at the class level
// so plain `nonisolated` applies below, no `unsafe` escape hatch needed.
private final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

@Observable @MainActor
final class PINEntryViewModel {
    var pinInput: String = ""
    var isShaking: Bool = false
    var eyesOpen: Bool = true
    var errorMessage: String = ""
    var showForgotPINSheet: Bool = false
    var isLockedOut: Bool = false
    var lockoutMessage: String = ""

    private let pinService: PINService
    let authService: BiometricAuthService
    // Only deinit (nonisolated) needs access off the main actor; every other read/write
    // here already runs on MainActor. Task.cancel() is thread-safe regardless.
    private nonisolated let countdownBox = TaskBox()

    var showBiometricButton: Bool {
        authService.isBiometricFeatureEnabled && authService.isBiometricsAvailable
    }

    var biometricIcon: String {
        let ctx = LAContext()
        return ctx.biometryType == .touchID ? "touchid" : "faceid"
    }

    init(pinService: PINService, authService: BiometricAuthService) {
        self.pinService = pinService
        self.authService = authService
    }

    /// Re-syncs the UI to the lockout state persisted in the Keychain.
    /// Called on every appearance because the lockout survives a force-quit but the
    /// view model doesn't: on a cold launch mid-lockout, nothing had consulted
    /// `pinService.lockoutDeadline`, so the pad rendered enabled with no countdown
    /// until the user burned another 4 digits and got `.lockedOut` back from
    /// `verifyPIN`. The lockout was always *enforced* (validatePINWithResult
    /// short-circuits before hashing) — this only restores the matching UI.
    func refreshLockoutState() {
        if let deadline = pinService.lockoutDeadline {
            startLockoutCountdown(until: deadline)
        } else if isLockedOut {
            // Deadline elapsed while this view model wasn't running its countdown.
            countdownBox.task?.cancel()
            countdownBox.task = nil
            isLockedOut = false
            lockoutMessage = ""
            errorMessage = ""
            pinInput = ""
            eyesOpen = true
        }
    }

    func appendDigit(_ digit: String) {
        guard !isLockedOut else { return }
        guard pinInput.count < 4 else { return }
        pinInput += digit
        eyesOpen = false
        if pinInput.count == 4 {
            Task { try? await Task.sleep(for: .seconds(0.15)); self.verifyPIN() }
        }
    }

    func deleteDigit() {
        if !pinInput.isEmpty { pinInput.removeLast() }
        eyesOpen = pinInput.isEmpty
    }

    func triggerBiometric() {
        authService.authenticate { _ in }
    }

    func triggerForgotPIN() {
        authService.authenticate { [weak self] success in
            if success {
                self?.showForgotPINSheet = true
            } else {
                self?.errorMessage = "Biometric authentication required to reset PIN"
            }
        }
    }

    private func verifyPIN() {
        let result = pinService.validatePINWithResult(pinInput)
        switch result {
        case .success:
            authService.unlock()
            pinInput = ""
            eyesOpen = true
        case .failure(let remainingAttempts):
            errorMessage = "Incorrect PIN. \(remainingAttempts) attempt\(remainingAttempts == 1 ? "" : "s") remaining."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        case .lockedOut(let deadline):
            startLockoutCountdown(until: deadline)
        }
    }

    private func startLockoutCountdown(until deadline: Date) {
        countdownBox.task?.cancel()
        isLockedOut = true
        // Paint the first message synchronously. The Task below only gets to run on a
        // later tick, which would otherwise leave the pad disabled with no explanation
        // for a frame — most visible on a cold launch mid-lockout, where the countdown
        // is the only thing telling the user why nothing responds.
        updateLockoutMessage(until: deadline)

        countdownBox.task = Task {
            while !Task.isCancelled {
                let now = Date()
                if now >= deadline {
                    // Lockout expired
                    isLockedOut = false
                    lockoutMessage = ""
                    errorMessage = ""
                    pinInput = ""
                    eyesOpen = true
                    countdownBox.task = nil
                    break
                }

                updateLockoutMessage(until: deadline)

                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
            }
        }
    }

    private func updateLockoutMessage(until deadline: Date) {
        let remainingSeconds = max(1, Int(deadline.timeIntervalSince(Date())) + 1)
        lockoutMessage = "Locked out. Try again in \(remainingSeconds)s."
        errorMessage = lockoutMessage
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }

    deinit {
        countdownBox.task?.cancel()
    }
}
