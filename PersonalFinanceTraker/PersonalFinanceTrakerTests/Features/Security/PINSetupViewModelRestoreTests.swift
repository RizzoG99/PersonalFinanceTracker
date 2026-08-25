import Testing
import Foundation
import CryptoKit
@testable import PersonalFinanceTraker

private final class FakeBiometricAuthService: BiometricAuthenticating {
    var isBiometricsAvailable: Bool = false
    var biometricLabel: String = "Face ID"
    var isLockEnabled: Bool = false

    func authenticateToEnable(completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}

extension PINKeychainSerialTests {

@MainActor
@Suite(.serialized)
struct PINSetupViewModelRestoreTests {
    private let pinService = PINService()
    private let backupKey = SymmetricKey(size: .bits256)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeBackedUpService() throws -> BackupService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = BackupService(storage: TestBackupStorage(url: dir), maxBackupsKept: 3, keyProvider: { backupKey })
        _ = try service.writeBackup(
            transactions: [.test(timestamp: date(2026, 1, 5), amount: -42, note: "Lunch", category: "Food")],
            recurrenceRules: [],
            now: date(2026, 1, 6)
        )
        return service
    }

    private func makeEmptyService() -> BackupService {
        BackupService(storage: TestBackupStorage(url: nil), maxBackupsKept: 3, keyProvider: { self.backupKey })
    }

    /// Drives digit entry through to `.nameEntry`, matching `PINSetupViewModelTests`' helper.
    private func advanceToNameEntry(on viewModel: PINSetupViewModel) async throws {
        for digit in "1234" { viewModel.appendDigit(String(digit)) }
        for _ in 0..<40 where viewModel.currentStep != .confirmPin {
            try await Task.sleep(for: .milliseconds(50))
        }
        for digit in "1234" { viewModel.appendDigit(String(digit)) }
        for _ in 0..<80 where viewModel.currentStep != .nameEntry {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("finishNameEntry moves to restorePrompt when a backup exists")
    func finishNameEntryEntersRestorePromptWhenBackupExists() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let repo = MockTransactionRepository()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: FakeBiometricAuthService(),
            showsOnboardingExtras: true,
            restoreRepo: repo,
            backupService: try makeBackedUpService()
        )

        try await advanceToNameEntry(on: viewModel)
        viewModel.finishNameEntry()

        #expect(viewModel.currentStep == .restorePrompt)
        #expect(!UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }

    @Test("finishNameEntry finishes onboarding directly when no backup exists")
    func finishNameEntrySkipsRestorePromptWhenNoBackup() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let repo = MockTransactionRepository()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: FakeBiometricAuthService(),
            showsOnboardingExtras: true,
            restoreRepo: repo,
            backupService: makeEmptyService()
        )

        try await advanceToNameEntry(on: viewModel)
        viewModel.finishNameEntry()

        #expect(viewModel.currentStep != .restorePrompt)
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }

    @Test("restoreFromBackup restores into the repo then finishes onboarding")
    func restoreFromBackupRestoresAndFinishes() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let repo = MockTransactionRepository()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: FakeBiometricAuthService(),
            showsOnboardingExtras: true,
            restoreRepo: repo,
            backupService: try makeBackedUpService()
        )
        viewModel.currentStep = .restorePrompt

        viewModel.restoreFromBackup()
        for _ in 0..<40 where !UserDefaults.standard.bool(forKey: "pin_setup_complete") {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(repo.deleteAllTransactionsCalledCount == 1)
        #expect(repo.addCalledCount == 1)
        #expect(!viewModel.isRestoring)
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }

    @Test("skipRestore finishes onboarding without touching the repo")
    func skipRestoreFinishesWithoutRestoring() {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let repo = MockTransactionRepository()
        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: FakeBiometricAuthService(),
            showsOnboardingExtras: true,
            restoreRepo: repo,
            backupService: makeEmptyService()
        )
        viewModel.currentStep = .restorePrompt

        viewModel.skipRestore()

        #expect(repo.deleteAllTransactionsCalledCount == 0)
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }

    @Test("finishNameEntry never restore-prompts when not wired to a repo (PIN change/reset)")
    func finishNameEntrySkipsWhenNoRestoreRepo() async throws {
        defer {
            try? pinService.clearPIN()
            UserDefaults.standard.removeObject(forKey: "pin_setup_complete")
        }
        UserDefaults.standard.removeObject(forKey: "pin_setup_complete")

        let viewModel = PINSetupViewModel(
            pinService: pinService,
            authService: FakeBiometricAuthService(),
            showsOnboardingExtras: true,
            backupService: try makeBackedUpService()
        )

        try await advanceToNameEntry(on: viewModel)
        viewModel.finishNameEntry()

        #expect(viewModel.currentStep != .restorePrompt)
        #expect(UserDefaults.standard.bool(forKey: "pin_setup_complete"))
    }
}

}
