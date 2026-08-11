import SwiftUI

@Observable @MainActor
final class PINSetupViewModel {
    enum SetupStep { case verifyCurrentPin, enterPin, confirmPin, success, biometricPrompt, nameEntry }

    var currentStep: SetupStep = .enterPin
    var pinInput: String = ""
    var confirmInput: String = ""
    var fullName: String = ""
    var errorMessage: String = ""
    var isShaking: Bool = false
    var isBouncing: Bool = false
    var eyesOpen: Bool = true
    var isComplete: Bool = false

    let isChangeMode: Bool
    let showsOnboardingExtras: Bool
    private let pinService: PINService
    private let authService: BiometricAuthenticating
    private var firstPin: String = ""

    var biometricLabel: String { authService.biometricLabel }

    init(
        pinService: PINService,
        authService: BiometricAuthenticating,
        isChangeMode: Bool = false,
        showsOnboardingExtras: Bool = false
    ) {
        self.pinService = pinService
        self.authService = authService
        self.isChangeMode = isChangeMode
        self.showsOnboardingExtras = showsOnboardingExtras
        currentStep = isChangeMode ? .verifyCurrentPin : .enterPin
    }

    func appendDigit(_ digit: String) {
        switch currentStep {
        case .verifyCurrentPin:
            guard pinInput.count < 4 else { return }
            pinInput += digit
            eyesOpen = false
            if pinInput.count == 4 {
                Task { try? await Task.sleep(for: .seconds(0.15)); self.verifyCurrentPIN() }
            }
        case .enterPin:
            guard pinInput.count < 4 else { return }
            pinInput += digit
            eyesOpen = false
            if pinInput.count == 4 {
                Task { try? await Task.sleep(for: .seconds(0.15)); self.advanceToConfirm() }
            }
        case .confirmPin:
            guard confirmInput.count < 4 else { return }
            confirmInput += digit
            eyesOpen = false
            if confirmInput.count == 4 {
                Task { try? await Task.sleep(for: .seconds(0.15)); self.validateAndSave() }
            }
        case .success, .biometricPrompt, .nameEntry:
            break
        }
    }

    func deleteDigit() {
        switch currentStep {
        case .verifyCurrentPin, .enterPin:
            if !pinInput.isEmpty { pinInput.removeLast() }
            eyesOpen = pinInput.isEmpty
        case .confirmPin:
            if !confirmInput.isEmpty { confirmInput.removeLast() }
            eyesOpen = confirmInput.isEmpty
        case .success, .biometricPrompt, .nameEntry:
            break
        }
    }

    func goBackToEnterPin() {
        currentStep = .enterPin
        pinInput = ""
        confirmInput = ""
        firstPin = ""
        errorMessage = ""
        eyesOpen = true
    }

    private func verifyCurrentPIN() {
        let result = pinService.validatePINWithResult(pinInput)
        switch result {
        case .success:
            pinInput = ""
            eyesOpen = true
            errorMessage = ""
            withAnimation { currentStep = .enterPin }
        case .failure(let remainingAttempts):
            errorMessage = "Incorrect PIN. \(remainingAttempts) attempt\(remainingAttempts == 1 ? "" : "s") remaining."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        case .lockedOut(let deadline):
            errorMessage = "Account locked. Try again later."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        }
    }

    private func advanceToConfirm() {
        if isChangeMode && pinService.verifyPINForPolicyCheck(pinInput) {
            errorMessage = "New PIN must be different from the current one."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
            return
        }
        firstPin = pinInput
        pinInput = ""
        errorMessage = ""
        eyesOpen = true
        withAnimation { currentStep = .confirmPin }
    }

    private func validateAndSave() {
        guard confirmInput == firstPin else {
            errorMessage = "PINs don't match. Try again."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.confirmInput = ""; self.eyesOpen = true }
            return
        }

        do {
            try pinService.clearPIN()
            try pinService.setPIN(firstPin)
        } catch {
            errorMessage = "Failed to save PIN. Try again."
            triggerShake()
            confirmInput = ""
            eyesOpen = true
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = .success
        }
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) {
                self.isBouncing = true
            }
            try? await Task.sleep(for: .seconds(1.3))
            if self.isChangeMode {
                self.isComplete = true
            } else if self.showsOnboardingExtras {
                self.advanceToBiometricPrompt()
            } else {
                self.finishOnboarding()
            }
        }
    }

    private func advanceToBiometricPrompt() {
        guard authService.isBiometricsAvailable else {
            currentStep = .nameEntry
            return
        }
        withAnimation { currentStep = .biometricPrompt }
    }

    func enableBiometric() {
        errorMessage = ""
        authService.authenticateToEnable { success in
            if success {
                self.authService.isLockEnabled = true
                withAnimation { self.currentStep = .nameEntry }
            } else {
                self.errorMessage = "Couldn't verify — you can set this up later in Profile."
            }
        }
    }

    func skipBiometric() {
        errorMessage = ""
        withAnimation { currentStep = .nameEntry }
    }

    func finishNameEntry() {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: "user_full_name")
        }
        finishOnboarding()
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "pin_setup_complete")
        NotificationCenter.default.post(name: .pinSetupComplete, object: nil)
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }
}
