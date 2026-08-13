import Testing
import Foundation

@testable import PersonalFinanceTraker

extension PINKeychainSerialTests {

@Suite(.serialized)
@MainActor
struct PINConfirmationViewModelTests {
    private let pinService = PINService()

    @Test("Correct PIN entered digit-by-digit invokes onConfirmed callback")
    func correctPINEntered() async throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        var onConfirmedCalled = false
        let viewModel = PINConfirmationViewModel(pinService: pinService) {
            onConfirmedCalled = true
        }

        viewModel.appendDigit("1")
        viewModel.appendDigit("2")
        viewModel.appendDigit("3")
        viewModel.appendDigit("4")

        #expect(viewModel.pinInput == "1234")
        #expect(!onConfirmedCalled)

        // The view model waits 0.15s before verifying. Poll for the result rather
        // than sleeping past it: a fixed wait tuned on an idle machine came up
        // short under full-suite load and made this test intermittently fail.
        #expect(await waitUntil { onConfirmedCalled })
        #expect(viewModel.errorMessage.isEmpty)
    }

    @Test("Incorrect PIN entered does not invoke onConfirmed")
    func incorrectPINEntered() async throws {
        defer { try? pinService.clearPIN() }

        try pinService.setPIN("1234")

        var onConfirmedCalled = false
        let viewModel = PINConfirmationViewModel(pinService: pinService) {
            onConfirmedCalled = true
        }

        viewModel.appendDigit("5")
        viewModel.appendDigit("6")
        viewModel.appendDigit("7")
        viewModel.appendDigit("8")

        #expect(viewModel.pinInput == "5678")

        // Wait for the rejection to land, then assert the callback never fired.
        #expect(await waitUntil { !viewModel.errorMessage.isEmpty })
        #expect(!onConfirmedCalled)
        #expect(viewModel.isShaking)

        // The view model clears the input ~0.6s after the last digit (0.15s verify
        // delay + 0.45s reset delay). Poll for the reset instead of racing it.
        #expect(await waitUntil { viewModel.pinInput.isEmpty })
        #expect(viewModel.eyesOpen)
    }

    @Test("appendDigit does not append beyond 4 digits")
    func appendDigitBoundary() {
        var onConfirmedCalled = false
        let viewModel = PINConfirmationViewModel(pinService: pinService) {
            onConfirmedCalled = true
        }

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
        var onConfirmedCalled = false
        let viewModel = PINConfirmationViewModel(pinService: pinService) {
            onConfirmedCalled = true
        }

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
