import SwiftUI

struct PINSetupView: View {
    @State var viewModel: PINSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PINScreenLayout(
            eyesOpen: $viewModel.eyesOpen,
            isShaking: viewModel.isShaking,
            isBouncing: viewModel.isBouncing,
            title: stepTitle,
            errorMessage: viewModel.errorMessage,
            filledCount: showsPINDots ? currentFilledCount : nil
        ) {
            stepContent
        } footer: {
            if viewModel.currentStep == .confirmPin {
                Button("Go back") { viewModel.goBackToEnterPin() }
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .navigationTitle(viewModel.isChangeMode ? "Change PIN" : "")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!viewModel.isChangeMode)
        .onChange(of: viewModel.isComplete) { _, done in
            if done { dismiss() }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .success:
            successContent
        case .biometricPrompt:
            biometricPromptContent
        case .nameEntry:
            nameEntryContent
        case .verifyCurrentPin, .enterPin, .confirmPin:
            PINPadView(
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() }
            )
            .transition(.opacity)
        }
    }

    private var showsPINDots: Bool {
        switch viewModel.currentStep {
        case .verifyCurrentPin, .enterPin, .confirmPin, .success: return true
        case .biometricPrompt, .nameEntry: return false
        }
    }

    private var stepTitle: LocalizedStringKey {
        switch viewModel.currentStep {
        case .verifyCurrentPin: return "Enter current PIN"
        case .enterPin:         return "Enter new PIN"
        case .confirmPin:       return "Confirm new PIN"
        case .success:          return "PIN successfully set"
        case .biometricPrompt:  return "Unlock with \(viewModel.biometricLabel)"
        case .nameEntry:        return "What should we call you?"
        }
    }

    private var currentFilledCount: Int {
        switch viewModel.currentStep {
        case .verifyCurrentPin, .enterPin: return viewModel.pinInput.count
        case .confirmPin:                  return viewModel.confirmInput.count
        case .success, .biometricPrompt, .nameEntry: return 4
        }
    }

    private var successContent: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(.accentIndigo)
            .transition(.scale.combined(with: .opacity))
    }

    private var biometricPromptContent: some View {
        VStack(spacing: 16) {
            Button {
                viewModel.enableBiometric()
            } label: {
                Text("Set Up \(viewModel.biometricLabel)")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentIndigo, in: RoundedRectangle(cornerRadius: 14))
            }

            Button("Skip") { viewModel.skipBiometric() }
                .font(.subheadline)
                .foregroundStyle(.textDim)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .transition(.opacity)
    }

    private var nameEntryContent: some View {
        VStack(spacing: 16) {
            TextField("Your name", text: $viewModel.fullName)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit { viewModel.finishNameEntry() }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))

            Button {
                viewModel.finishNameEntry()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentIndigo, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    PINSetupView(viewModel: PINSetupViewModel(pinService: PINService(), authService: BiometricAuthService()))
}
