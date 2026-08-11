import SwiftUI
import LocalAuthentication

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
    private var countdownTask: Task<Void, Never>?

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
        case .failure(let remainingAttempts):
            errorMessage = "Incorrect PIN. \(remainingAttempts) attempt\(remainingAttempts == 1 ? "" : "s") remaining."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        case .lockedOut(let deadline):
            startLockoutCountdown(until: deadline)
        }
    }

    private func startLockoutCountdown(until deadline: Date) {
        countdownTask?.cancel()
        isLockedOut = true

        countdownTask = Task {
            while !Task.isCancelled {
                let now = Date()
                if now >= deadline {
                    // Lockout expired
                    isLockedOut = false
                    lockoutMessage = ""
                    errorMessage = ""
                    pinInput = ""
                    eyesOpen = true
                    countdownTask = nil
                    break
                }

                let remainingSeconds = Int(deadline.timeIntervalSince(now)) + 1
                lockoutMessage = "Locked out. Try again in \(remainingSeconds)s."
                errorMessage = lockoutMessage

                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
            }
        }
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }

    deinit {
        countdownTask?.cancel()
    }
}
