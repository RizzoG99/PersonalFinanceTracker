import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    @Environment(\.dismiss) private var dismiss
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @State private var showingFileImporter = false

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
                        ProfilePayCycleSection()
                    }
                    .appFormSectionBackground()
                    Section {
                        ProfileCategoriesSection(selectedDetent: $selectedDetent)
                    }
                    .appFormSectionBackground()
                    Section {
                        Button {
                            showingFileImporter = true
                        } label: {
                            if transactionViewModel.isLoadingCSV {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reading file…")
                                }
                            } else {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(transactionViewModel.isLoadingCSV)
                    } header: {
                        Text("DATA")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textDim)
                            .padding(.horizontal, 4)
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
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                switch result {
                case .success(let url):
                    dismiss()
                    transactionViewModel.loadCSVFile(from: url)
                case .failure(let error):
                    transactionViewModel.importError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ProfileView(viewModel: ProfileViewModel(), selectedDetent: .constant(.large))
}
