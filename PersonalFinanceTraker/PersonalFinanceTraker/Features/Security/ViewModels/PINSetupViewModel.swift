import SwiftUI
import Combine

final class PINSetupViewModel: ObservableObject {
    enum SetupStep { case verifyCurrentPin, enterPin, confirmPin, success }

    @Published var currentStep: SetupStep = .enterPin
    @Published var pinInput: String = ""
    @Published var confirmInput: String = ""
    @Published var errorMessage: String = ""
    @Published var isShaking: Bool = false
    @Published var isBouncing: Bool = false
    @Published var eyesOpen: Bool = true
    @Published var isComplete: Bool = false

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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.verifyCurrentPIN() }
            }
        case .enterPin:
            guard pinInput.count < 4 else { return }
            pinInput += digit
            eyesOpen = false
            if pinInput.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.advanceToConfirm() }
            }
        case .confirmPin:
            guard confirmInput.count < 4 else { return }
            confirmInput += digit
            eyesOpen = false
            if confirmInput.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.validateAndSave() }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.pinInput = ""
                self.eyesOpen = true
            }
        }
    }

    private func advanceToConfirm() {
        if isChangeMode && pinService.validatePIN(pinInput) {
            errorMessage = "New PIN must be different from the current one."
            triggerShake()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.pinInput = ""
                self.eyesOpen = true
            }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.confirmInput = ""
                self.eyesOpen = true
            }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) {
                self.isBouncing = true
            }
        }

        if isChangeMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.isComplete = true
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                UserDefaults.standard.set(true, forKey: "pin_setup_complete")
                NotificationCenter.default.post(name: .pinSetupComplete, object: nil)
            }
        }
    }

    private func triggerShake() {
        isShaking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isShaking = false }
    }
}
