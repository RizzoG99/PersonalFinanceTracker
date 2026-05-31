import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProfileHeader(displayName: viewModel.displayName, memberSince: viewModel.memberSince)
                Form {
                    Section {
                        ProfilePersonalInfoSection(fullName: $viewModel.fullName)
                    }
                    .appFormSectionBackground()
                    Section {
                        ProfileCurrencySection()
                    }
                    .appFormSectionBackground()
                    Section {
                        ProfileCategoriesSection(selectedDetent: $selectedDetent)
                    }
                    .appFormSectionBackground()
                    Section {
                        ProfileSecuritySection(viewModel: viewModel, selectedDetent: $selectedDetent)
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
}

#Preview {
    ProfileView(viewModel: ProfileViewModel(), selectedDetent: .constant(.large))
}
