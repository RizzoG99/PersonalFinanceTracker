import SwiftUI
import LocalAuthentication

@Observable @MainActor
final class PINEntryViewModel {
    var pinInput: String = ""
    var isShaking: Bool = false
    var eyesOpen: Bool = true
    var errorMessage: String = ""
    var showForgotPINSheet: Bool = false

    private let pinService: PINService
    let authService: BiometricAuthService

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
        if pinService.validatePIN(pinInput) {
            authService.unlock()
        } else {
            errorMessage = "Incorrect PIN. Try again."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        }
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }
}
