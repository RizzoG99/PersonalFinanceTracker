import SwiftUI

struct ProfileSecuritySection: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    @Binding var route: ProfileRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SECURITY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textDim)
                .padding(.horizontal, 4)
            VStack {
                Button {
                    selectedDetent = .large
                    route = .changePIN
                } label: {
                    HStack {
                        Text("Change PIN")
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.textDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
