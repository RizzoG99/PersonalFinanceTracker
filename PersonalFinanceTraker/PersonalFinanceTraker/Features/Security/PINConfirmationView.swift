import SwiftUI

struct PINConfirmationView: View {
    @State var viewModel: PINConfirmationViewModel
    let onCancel: () -> Void

    var body: some View {
        PINScreenLayout(
            eyesOpen: $viewModel.eyesOpen,
            isShaking: viewModel.isShaking,
            // "Confirm your PIN" is what the PIN *setup* flow says on its second step, so here
            // it read as "set a PIN" rather than "prove it's you before erasing everything".
            title: "Enter your PIN",
            subtitle: "Required before erasing all data",
            errorMessage: viewModel.errorMessage,
            filledCount: viewModel.pinInput.count
        ) {
            PINPadView(
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() }
            )
        } footer: {
            // A wrong guess here spends an attempt from the app-wide lockout budget, so a user who
            // opened this by accident and can't back out can lock themselves out of the whole app.
            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(.textMid)
                .frame(minWidth: 44, minHeight: 44)
        }
    }
}

#Preview {
    PINConfirmationView(
        viewModel: PINConfirmationViewModel(pinService: PINService(), onConfirmed: {}),
        onCancel: {}
    )
}
