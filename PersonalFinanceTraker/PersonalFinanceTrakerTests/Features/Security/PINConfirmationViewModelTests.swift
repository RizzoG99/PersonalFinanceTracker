import Testing
import Foundation

@testable import PersonalFinanceTraker

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

        try await Task.sleep(for: .seconds(0.3))

        #expect(onConfirmedCalled)
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

        try await Task.sleep(for: .seconds(0.3))

        #expect(!onConfirmedCalled)
        #expect(!viewModel.errorMessage.isEmpty)
        #expect(viewModel.isShaking)

        // ponytail: reset fires ~0.6s after last digit (0.15s verify delay +
        // 0.45s reset delay in the view model); wait past that with margin
        // instead of matching it exactly.
        try await Task.sleep(for: .seconds(0.5))

        #expect(viewModel.pinInput.isEmpty)
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
