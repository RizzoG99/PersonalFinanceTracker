import SwiftUI

struct PINConfirmationView: View {
    @State var viewModel: PINConfirmationViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MonkeyAnimationView(
                eyesOpen: $viewModel.eyesOpen,
                isShaking: viewModel.isShaking
            )
            .padding(.bottom, 32)

            VStack(spacing: 8) {
                Text("Confirm your PIN")
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

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}

#Preview {
    PINConfirmationView(viewModel: PINConfirmationViewModel(pinService: PINService(), onConfirmed: {}))
}
