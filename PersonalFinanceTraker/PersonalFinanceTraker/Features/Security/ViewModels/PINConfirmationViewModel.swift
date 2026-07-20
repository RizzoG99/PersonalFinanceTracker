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
        if pinService.validatePIN(pinInput) {
            onConfirmed()
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
