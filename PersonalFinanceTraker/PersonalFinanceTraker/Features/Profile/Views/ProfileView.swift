import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                profileHeader
                Form {
                    Section {
                        personalInfoSection
                    }
                    .appFormSectionBackground()
                    Section {
                        securitySection
                    }
                    .appFormSectionBackground()
                }
                .appFormBackground()
            }
            .padding(.top, 24)
            .appBackground()
            .preferredColorScheme(.dark)
            .navigationTitle("Settings")
            .onAppear { viewModel.checkBiometrics() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.textMid)
                            .padding(8)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 4) {
            Text(viewModel.displayName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.textPrimary)
            
            Text(viewModel.memberSince)
                .font(.subheadline)
                .foregroundStyle(.textDim)
        }
    }
    
    private var personalInfoSection: some View {
        TextField("Enter your name", text: $viewModel.fullName)
            .foregroundStyle(.textPrimary)
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Security")
            
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
    
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.textDim)
            .padding(.horizontal, 4)
    }
}

#Preview {
    ProfileView(viewModel: ProfileViewModel())
}
