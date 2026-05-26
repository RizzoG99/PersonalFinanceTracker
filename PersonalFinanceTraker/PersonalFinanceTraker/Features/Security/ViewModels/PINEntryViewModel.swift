import SwiftUI
import LocalAuthentication

final class PINEntryViewModel: ObservableObject {
    @Published var pinInput: String = ""
    @Published var isShaking: Bool = false
    @Published var eyesOpen: Bool = true
    @Published var errorMessage: String = ""

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.verifyPIN() }
        }
    }

    func deleteDigit() {
        if !pinInput.isEmpty { pinInput.removeLast() }
        eyesOpen = pinInput.isEmpty
    }

    func triggerBiometric() {
        authService.authenticate { _ in }
    }

    private func verifyPIN() {
        if pinService.validatePIN(pinInput) {
            authService.unlock()
        } else {
            errorMessage = "Incorrect PIN. Try again."
            triggerShake()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.pinInput = ""
                self.eyesOpen = true
            }
        }
    }

    private func triggerShake() {
        isShaking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isShaking = false }
    }
}
