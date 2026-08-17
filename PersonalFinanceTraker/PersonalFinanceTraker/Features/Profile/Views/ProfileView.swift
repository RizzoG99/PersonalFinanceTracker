import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import CoreTransferable

enum ProfileRoute: Hashable {
    case categories, budgets, changePIN
}

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel
    @Binding var selectedDetent: PresentationDetent
    /// Controls whether the close (✕) button is shown in the top-right. On iPhone the profile
    /// opens as a sheet and needs a dismiss affordance; on iPad it is a sidebar destination with
    /// standard navigation UI, so the button is unnecessary and confusing.
    var isHostedAsSheet: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(TransactionListViewModel.self) private var transactionViewModel: TransactionListViewModel
    @Environment(DataChangedSignal.self) private var dataChanged
    @Environment(AppSettings.self) private var appSettings
    @State private var showingFileImporter = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPINConfirmation = false
    @State private var showingDeleteSuccess = false
    @State private var deleteErrorMessage: String?
    @State private var backupErrorMessage: String?
    @State private var restoreErrorMessage: String?
    @State private var route: ProfileRoute?
    @State private var showingRestoreConfirmation = false
    private let pinService = PINService()
    private let authService = BiometricAuthService()
    private let backupService = BackupService()

    private var backupStatusTitle: String {
        guard let lastBackupDate = appSettings.lastBackupDate else {
            return "Not backed up"
        }
        let formatter = RelativeDateTimeFormatter()
        return "Last backup: \(formatter.localizedString(for: lastBackupDate, relativeTo: .now))"
    }

    private func runManualBackup() async {
        let transactions = (try? await transactionViewModel.repo.fetchAll()) ?? []
        let rules = (try? await transactionViewModel.repo.fetchAllRecurrenceRules()) ?? []
        do {
            try backupService.writeBackup(transactions: transactions, recurrenceRules: rules)
            appSettings.lastBackupDate = .now
        } catch BackupService.BackupError.emptyStore {
            backupErrorMessage = "No transactions to back up yet."
        } catch BackupService.BackupError.iCloudUnavailable {
            backupErrorMessage = "iCloud Drive is not available. Enable it in Settings to back up your data."
        } catch {
            backupErrorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProfileHeader(displayName: viewModel.displayName, memberSince: viewModel.memberSince)
                // ponytail: readableWidth caps form width on iPad to improve scanability (HIG
                // readable-content guidance). iPhone portrait is ~390pt, well under 640, so it's
                // unaffected. iPhone landscape is not supported by this app.
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
                        ProfileAppearanceSection()
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
                        ProfileCategoriesSection(selectedDetent: $selectedDetent, route: $route)
                    }
                    .appFormSectionBackground()
                    Section {
                        ProfileBudgetsSection(selectedDetent: $selectedDetent, route: $route)
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

                        VStack(alignment: .leading, spacing: 6) {
                            Label(backupStatusTitle, systemImage: appSettings.lastBackupDate != nil ? "checkmark.icloud" : "exclamationmark.icloud")
                                .foregroundStyle(appSettings.lastBackupDate != nil ? .textDim : .negative)

                            if appSettings.lastBackupDate == nil {
                                Text("Enable iCloud Drive to protect your data if the app is deleted.")
                                    .font(.caption)
                                    .foregroundStyle(.textDim)
                            }

                            Button("Back Up Now") {
                                Task { await runManualBackup() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)

                        Button {
                            showingRestoreConfirmation = true
                        } label: {
                            Label("Restore from Backup", systemImage: "arrow.clockwise.icloud")
                        }
                        .disabled(backupService.newestBackup() == nil)
                        .confirmationDialog(
                            "This replaces all current data with your last backup. This cannot be undone.",
                            isPresented: $showingRestoreConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Restore", role: .destructive) {
                                Task {
                                    do {
                                        try await RestoreService.restoreLatest(repo: transactionViewModel.repo, backupService: backupService)
                                        dataChanged.bump()
                                    } catch BackupService.BackupError.decryptionFailed {
                                        restoreErrorMessage = "Backup can't be decrypted. Make sure iCloud Keychain is enabled on this device."
                                    } catch {
                                        restoreErrorMessage = error.localizedDescription
                                    }
                                }
                            }
                            Button("Cancel", role: .cancel) {}
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
                        ProfileSecuritySection(viewModel: viewModel, selectedDetent: $selectedDetent, route: $route)
                    }
                    .appFormSectionBackground()
                }
                .appFormBackground()
                .navigationDestination(item: $route) { route in
                    switch route {
                    case .categories: CategorySettingsView()
                    case .budgets: BudgetsView()
                    case .changePIN:
                        PINSetupView(
                            viewModel: PINSetupViewModel(pinService: pinService, authService: authService, isChangeMode: true)
                        )
                    }
                }
            }
            .readableWidth()
            .padding(.top, 24)
            .appBackground()
            .navigationTitle("Settings")
            .onAppear { viewModel.checkBiometrics() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isHostedAsSheet {
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
                    },
                    onCancel: { showingPINConfirmation = false }
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
            .alert(
                "Backup Failed",
                isPresented: Binding(
                    get: { backupErrorMessage != nil },
                    set: { if !$0 { backupErrorMessage = nil } }
                )
            ) {
                Button("OK") { backupErrorMessage = nil }
            } message: {
                Text(backupErrorMessage ?? "")
            }
            .alert(
                "Restore Failed",
                isPresented: Binding(
                    get: { restoreErrorMessage != nil },
                    set: { if !$0 { restoreErrorMessage = nil } }
                )
            ) {
                Button("OK") { restoreErrorMessage = nil }
            } message: {
                Text(restoreErrorMessage ?? "")
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
