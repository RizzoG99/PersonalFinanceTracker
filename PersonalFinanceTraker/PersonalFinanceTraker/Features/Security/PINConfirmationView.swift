import SwiftUI

struct PINConfirmationView: View {
    @State var viewModel: PINConfirmationViewModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            MonkeyAnimationView(
                eyesOpen: $viewModel.eyesOpen,
                isShaking: viewModel.isShaking
            )
            .padding(.bottom, 32)

            VStack(spacing: 8) {
                // "Confirm your PIN" is what the PIN *setup* flow says on its second step, so here
                // it read as "set a PIN" rather than "prove it's you before erasing everything".
                Text("Enter your PIN")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.textPrimary)

                Text("Required before erasing all data")
                    .font(.subheadline)
                    .foregroundStyle(.textDim)

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

            // A wrong guess here spends an attempt from the app-wide lockout budget, so a user who
            // opened this by accident and can't back out can lock themselves out of the whole app.
            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(.textMid)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.top, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}

#Preview {
    PINConfirmationView(
        viewModel: PINConfirmationViewModel(pinService: PINService(), onConfirmed: {}),
        onCancel: {}
    )
}
