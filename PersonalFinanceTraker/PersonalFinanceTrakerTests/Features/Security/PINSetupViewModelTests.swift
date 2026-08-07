import Testing
import Foundation

@testable import PersonalFinanceTraker

private final class FakeBiometricAuthService: BiometricAuthenticating {
    var isBiometricsAvailable: Bool
    var biometricLabel: String = "Face ID"
    var isLockEnabled: Bool = false
    var authenticateResult: Bool = true

    init(isBiometricsAvailable: Bool = true) {
        self.isBiometricsAvailable = isBiometricsAvailable
    }

    func authenticateToEnable(completion: @escaping (Bool) -> Void) {
        completion(authenticateResult)
    }
}

@MainActor
@Suite(.serialized)
struct PINSetupViewModelTests {
    private let pinService = PINService()

    /// Drives digit entry for a full enter+confirm PIN cycle. Callers still need to
    /// wait out validateAndSave's own bounce-animation delay afterward.
    private func enterAndConfirmPIN(_ pin: String, on viewModel: PINSetupViewModel) async throws {
        for digit in pin { viewModel.appendDigit(String(digit)) }
        try await Task.sleep(for: .seconds(0.25))
        for digit in pin { viewModel.appendDigit(String(digit)) }
    }

    @Test("Full onboarding flow reaches nameEntry and finalizes")
    func fullFlowReachesNameEntryAndFinalizes() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
            UserDefaults.standard.removeObject(forKey: "user_full_name")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )

        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.3))

        #expect(viewModel.currentStep == .biometricPrompt)

        viewModel.skipBiometric()
        #expect(viewModel.currentStep == .nameEntry)
        #expect(!authService.isLockEnabled)

        viewModel.fullName = "Ada"
        viewModel.finishNameEntry()

        #expect(UserDefaults.standard.string(forKey: "user_full_name") == "Ada")
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }

    @Test("biometricPrompt auto-skips to nameEntry when biometrics unavailable")
    func biometricPromptAutoSkipsWhenUnavailable() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }

        let authService = FakeBiometricAuthService(isBiometricsAvailable: false)
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )

        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.3))

        #expect(viewModel.currentStep == .nameEntry)
    }

    @Test("Skip link on biometricPrompt advances without enabling the lock")
    func biometricSkipDoesNotEnableLock() {
        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .biometricPrompt

        viewModel.skipBiometric()

        #expect(viewModel.currentStep == .nameEntry)
        #expect(!authService.isLockEnabled)
    }

    @Test("Successful biometric enable sets isLockEnabled and advances")
    func biometricEnableSuccessSetsLockEnabled() {
        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        authService.authenticateResult = true
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .biometricPrompt

        viewModel.enableBiometric()

        #expect(authService.isLockEnabled)
        #expect(viewModel.currentStep == .nameEntry)
        #expect(viewModel.errorMessage.isEmpty)
    }

    @Test("Failed biometric enable shows an error and stays on biometricPrompt")
    func biometricEnableFailureShowsError() {
        let authService = FakeBiometricAuthService(isBiometricsAvailable: true)
        authService.authenticateResult = false
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .biometricPrompt

        viewModel.enableBiometric()

        #expect(!authService.isLockEnabled)
        #expect(viewModel.currentStep == .biometricPrompt)
        #expect(!viewModel.errorMessage.isEmpty)
    }

    @Test("Name is trimmed before saving")
    func nameIsTrimmedBeforeSaving() {
        defer { UserDefaults.standard.removeObject(forKey: "user_full_name") }
        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .nameEntry
        viewModel.fullName = "  Ada Lovelace  "

        viewModel.finishNameEntry()

        #expect(UserDefaults.standard.string(forKey: "user_full_name") == "Ada Lovelace")
    }

    @Test("Whitespace-only name is not saved")
    func whitespaceOnlyNameIsNotSaved() {
        defer { UserDefaults.standard.removeObject(forKey: "user_full_name") }
        UserDefaults.standard.removeObject(forKey: "user_full_name")
        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            showsOnboardingExtras: true
        )
        viewModel.currentStep = .nameEntry
        viewModel.fullName = "   "

        viewModel.finishNameEntry()

        #expect(UserDefaults.standard.string(forKey: "user_full_name") == nil)
    }

    @Test("Change-PIN flow stops at success and never reaches the new steps")
    func changePINFlowStopsAtSuccess() async throws {
        defer { try? pinService.clearPIN() }
        try pinService.setPIN("0000")

        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            isChangeMode: true
        )

        for digit in "0000" { viewModel.appendDigit(String(digit)) }
        try await Task.sleep(for: .seconds(0.25))
        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.3))

        #expect(viewModel.currentStep == .success)
        #expect(viewModel.isComplete)
    }

    @Test("Forgot-PIN reset flow finalizes immediately and never reaches the new steps")
    func forgotPINResetFinalizesImmediately() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let authService = FakeBiometricAuthService()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: authService,
            isChangeMode: false,
            showsOnboardingExtras: false
        )

        try await enterAndConfirmPIN("1234", on: viewModel)
        try await Task.sleep(for: .seconds(2.3))

        #expect(viewModel.currentStep == .success)
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }
}
