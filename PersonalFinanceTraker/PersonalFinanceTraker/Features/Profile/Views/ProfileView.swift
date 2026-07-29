import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import CoreTransferable

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged
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
                        ProfileReminderSection()
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
                            if transactionViewModel.isLoadingImportFile {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reading file…")
                                }
                            } else {
                                Label("Import CSV or Excel", systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(transactionViewModel.isLoadingImportFile)

                        Menu {
                            ShareLink(
                                item: TransactionsExport(format: .csv, repo: transactionViewModel.repo),
                                preview: SharePreview("Transactions CSV")
                            ) {
                                Label("CSV", systemImage: "tablecells")
                            }

                            ShareLink(
                                item: TransactionsExport(format: .xlsx, repo: transactionViewModel.repo),
                                preview: SharePreview("Transactions Excel")
                            ) {
                                Label("Excel", systemImage: "tablecells.badge.ellipsis")
                            }
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete All Data", systemImage: "trash")
                                .foregroundStyle(.negative)
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
                allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "xlsx")!]
            ) { result in
                switch result {
                case .success(let url):
                    dismiss()
                    if url.pathExtension.lowercased() == "xlsx" {
                        transactionViewModel.loadExcelFile(from: url)
                    } else {
                        transactionViewModel.loadCSVFile(from: url)
                    }
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
            // Categories are core app data (needed to add a transaction), not sample
            // data — reseed immediately so the user isn't stuck until next launch.
            for category in SampleData.createSampleCategories() {
                modelContext.insert(category)
            }
            try modelContext.save()
            // DashboardViewModel/TransactionListViewModel cache their own in-memory
            // arrays; bump the shared signal so MainTabView reloads them (same
            // pattern EditAddTransactionView uses after a save/delete).
            dataChanged.bump()
            showingDeleteSuccess = true
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

/// Lazily exports all transactions when the user picks a destination in the
/// share sheet — nothing is fetched or written until then.
struct TransactionsExport: Transferable {
    enum Format: String {
        case csv, xlsx
    }

    let format: Format
    let repo: any ITransactionRepository

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            try await export.writeTempFile { Data(CSVExportService.generateCSV(from: $0).utf8) }
        }
        .exportingCondition { $0.format == .csv }

        FileRepresentation(exportedContentType: UTType(filenameExtension: "xlsx")!) { export in
            try await export.writeTempFile { try XLSXExportService.generateXLSX(from: $0) }
        }
        .exportingCondition { $0.format == .xlsx }
    }

    private func writeTempFile(_ make: ([TransactionSnapshot]) throws -> Data) async throws -> SentTransferredFile {
        let transactions = try await repo.fetchAll()
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Transactions-\(stamp).\(format.rawValue)")
        try make(transactions).write(to: url, options: .atomic)
        return SentTransferredFile(url)
    }
}

#Preview {
    ProfileView(viewModel: ProfileViewModel(), selectedDetent: .constant(.large))
}
