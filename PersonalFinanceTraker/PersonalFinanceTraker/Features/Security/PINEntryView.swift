import SwiftUI

struct PINEntryView: View {
    @State var viewModel: PINEntryViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MonkeyAnimationView(
                eyesOpen: $viewModel.eyesOpen,
                isShaking: viewModel.isShaking
            )
            .padding(.bottom, 32)

            VStack(spacing: 8) {
                Text("Enter your PIN")
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

            PINDotsView(filledCount: viewModel.pinInput.count)
                .padding(.bottom, 48)

            PINPadView(
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() }
            )

            if viewModel.showBiometricButton {
                Button(action: { viewModel.triggerBiometric() }) {
                    Image(systemName: viewModel.biometricIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(.accentIndigo)
                        .padding(.top, 32)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .preferredColorScheme(.dark)
    }
}
