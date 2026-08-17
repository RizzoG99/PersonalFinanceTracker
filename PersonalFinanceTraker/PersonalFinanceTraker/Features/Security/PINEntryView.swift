import SwiftUI

struct PINEntryView: View {
    @State var viewModel: PINEntryViewModel
    @State private var setupViewModel: PINSetupViewModel?

    var body: some View {
        PINScreenLayout(
            eyesOpen: $viewModel.eyesOpen,
            isShaking: viewModel.isShaking,
            title: "Enter your PIN",
            errorMessage: viewModel.errorMessage,
            filledCount: viewModel.pinInput.count
        ) {
            PINPadView(
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() }
            )
            .disabled(viewModel.isLockedOut)
            .opacity(viewModel.isLockedOut ? 0.5 : 1.0)
            .onAppear { viewModel.refreshLockoutState() }
        } footer: {
            if viewModel.showBiometricButton {
                VStack(spacing: 12) {
                    Button(action: { viewModel.triggerBiometric() }) {
                        Image(systemName: viewModel.biometricIcon)
                            .font(.system(size: 28))
                            .foregroundStyle(.accentIndigo)
                            .frame(minWidth: 44, minHeight: 44)
                    }

                    Button("Forgot PIN?") {
                        viewModel.triggerForgotPIN()
                    }
                    .font(.caption)
                    .foregroundStyle(.textDim)
                    .frame(minHeight: 44)
                }
            }
        }
        .sheet(isPresented: $viewModel.showForgotPINSheet) {
            if let setupViewModel = setupViewModel {
                PINSetupView(viewModel: setupViewModel)
            }
        }
        .onChange(of: viewModel.showForgotPINSheet) { _, isPresented in
            if isPresented {
                setupViewModel = PINSetupViewModel(
                    pinService: PINService(),
                    authService: viewModel.authService,
                    isChangeMode: false
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinSetupComplete)) { _ in
            viewModel.showForgotPINSheet = false
            setupViewModel = nil
        }
    }
}
