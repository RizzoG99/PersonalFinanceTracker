import SwiftUI

@Observable @MainActor
final class PINSetupViewModel {
    enum SetupStep { case verifyCurrentPin, enterPin, confirmPin, success }

    var currentStep: SetupStep = .enterPin
    var pinInput: String = ""
    var confirmInput: String = ""
    var errorMessage: String = ""
    var isShaking: Bool = false
    var isBouncing: Bool = false
    var eyesOpen: Bool = true
    var isComplete: Bool = false

    let isChangeMode: Bool
    private let pinService: PINService
    private var firstPin: String = ""

    init(pinService: PINService, isChangeMode: Bool = false) {
        self.pinService = pinService
        self.isChangeMode = isChangeMode
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
        case .success:
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
        case .success:
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
        if pinService.validatePIN(pinInput) {
            pinInput = ""
            eyesOpen = true
            errorMessage = ""
            withAnimation { currentStep = .enterPin }
        } else {
            errorMessage = "Incorrect PIN. Try again."
            triggerShake()
            Task { try? await Task.sleep(for: .seconds(0.45)); self.pinInput = ""; self.eyesOpen = true }
        }
    }

    private func advanceToConfirm() {
        if isChangeMode && pinService.validatePIN(pinInput) {
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
            if isChangeMode {
                self.isComplete = true
            } else {
                UserDefaults.standard.set(true, forKey: "pin_setup_complete")
                NotificationCenter.default.post(name: .pinSetupComplete, object: nil)
            }
        }
    }

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }
}
