import SwiftUI

struct PINSetupView: View {
    @StateObject var viewModel: PINSetupViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MonkeyAnimationView(
                eyesOpen: $viewModel.eyesOpen,
                isShaking: viewModel.isShaking,
                isBouncing: viewModel.isBouncing
            )
            .padding(.bottom, 32)

            VStack(spacing: 8) {
                Text(stepTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.textPrimary)

                if !viewModel.errorMessage.isEmpty {
                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.negative)
                        .transition(.opacity)
                        .animation(.easeInOut, value: viewModel.errorMessage)
                }
            }
            .padding(.bottom, 32)

            PINDotsView(filledCount: currentFilledCount)
                .padding(.bottom, 48)

            if viewModel.currentStep == .success {
                successContent
            } else {
                PINPadView(
                    onDigit: { viewModel.appendDigit($0) },
                    onDelete: { viewModel.deleteDigit() }
                )
                .transition(.opacity)
            }

            Spacer()

            if viewModel.currentStep == .confirmPin {
                Button("Go back") { viewModel.goBackToEnterPin() }
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
                    .padding(.bottom, 32)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .preferredColorScheme(.dark)
        .navigationTitle(viewModel.isChangeMode ? "Change PIN" : "")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!viewModel.isChangeMode)
        .onChange(of: viewModel.isComplete) { _, done in
            if done { dismiss() }
        }
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case .verifyCurrentPin: return "Enter current PIN"
        case .enterPin:         return "Enter new PIN"
        case .confirmPin:       return "Confirm new PIN"
        case .success:          return "PIN successfully set"
        }
    }

    private var currentFilledCount: Int {
        switch viewModel.currentStep {
        case .verifyCurrentPin, .enterPin: return viewModel.pinInput.count
        case .confirmPin:                  return viewModel.confirmInput.count
        case .success:                     return 4
        }
    }

    private var successContent: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(.accentIndigo)
            .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    PINSetupView(viewModel: PINSetupViewModel(pinService: PINService()))
}
