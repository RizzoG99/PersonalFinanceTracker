import SwiftUI

struct ProfileSecuritySection: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileSectionLabel(title: "Security")
            VStack {
                NavigationLink {
                    PINSetupView(
                        viewModel: PINSetupViewModel(
                            pinService: PINService(),
                            isChangeMode: true
                        )
                    )
                } label: {
                    Text("Change PIN")
                        .foregroundStyle(.textPrimary)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    selectedDetent = .large
                })

                if viewModel.isBiometricsAvailable {
                    Divider()
                        .padding(.vertical, 4)

                    Toggle(isOn: $viewModel.isBiometricEnabled) {
                        Text(viewModel.biometricLabel)
                            .foregroundStyle(.textPrimary)
                    }
                    .tint(Color.accentIndigo)
                }
            }
        }
    }
}
