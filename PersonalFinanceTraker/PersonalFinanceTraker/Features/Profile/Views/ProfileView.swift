import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @State private var showingFileImporter = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPINConfirmation = false
    @State private var showingDeleteSuccess = false
    @State private var deleteErrorMessage: String?
    private let pinService = PINService()

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

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete All Data", systemImage: "trash")
                        }
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
            .alert("Delete All Data?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if pinService.isPINSet() {
                        showingPINConfirmation = true
                    } else {
                        performWipe()
                    }
                }
            } message: {
                Text("This will permanently erase every transaction, category, credit card, and goal. This cannot be undone.")
            }
            .sheet(isPresented: $showingPINConfirmation) {
                PINConfirmationView(
                    viewModel: PINConfirmationViewModel(pinService: pinService) {
                        showingPINConfirmation = false
                        performWipe()
                    }
                )
            }
            .alert("All Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK") { dismiss() }
            }
            .alert(
                "Delete Failed",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("OK") { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func performWipe() {
        do {
            try DataWipeService.wipeAllData(context: modelContext)
            showingDeleteSuccess = true
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ProfileView(viewModel: ProfileViewModel(), selectedDetent: .constant(.large))
}
