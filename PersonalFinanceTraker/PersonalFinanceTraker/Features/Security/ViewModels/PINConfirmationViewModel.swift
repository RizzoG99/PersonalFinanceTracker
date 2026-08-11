import SwiftUI

@Observable @MainActor
final class PINConfirmationViewModel {
    var pinInput: String = ""
    var isShaking: Bool = false
    var eyesOpen: Bool = true
    var errorMessage: String = ""

    private let pinService: PINService
    private let onConfirmed: () -> Void

    init(pinService: PINService, onConfirmed: @escaping () -> Void) {
        self.pinService = pinService
        self.onConfirmed = onConfirmed
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

    private func verifyPIN() {
        let result = pinService.validatePINWithResult(pinInput)
        switch result {
        case .success:
            onConfirmed()
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

    private func triggerShake() {
        isShaking = true
        Task { try? await Task.sleep(for: .seconds(0.5)); self.isShaking = false }
    }
}
