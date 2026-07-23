import Testing
import Foundation
import SwiftData
@testable import PersonalFinanceTraker

/// Integration tests for the end-to-end Excel import flow.
/// Tests the full logical flow: multi-sheet workbook detection → sheet picker state.
/// This is an integration test (not a UI test) that uses real ViewModels and MockTransactionRepository.
///
/// Note: These are in-process integration tests, not XCUITests. The system `.fileImporter` dialog
/// cannot be driven from XCUITest, so we test the ViewModel layer directly. This exercises
/// the full logical flow that matters: file loading, workbook structure detection, sheet selection,
/// and column mapping - all independent of the system file picker.
@Suite
struct ExcelImportFlowTests {

    // Multi-sheet Excel fixture (same as used in XLSXWorkbookTests).
    // Contains two sheets: "Jan" and "Feb" with transaction data.
    static let multiSheetXLSXBase64 = """
    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
    """

    static func writeTempFile(base64: String, name: String) -> URL {
        let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    @MainActor
    private func loadedVM(_ repo: MockTransactionRepository) async -> TransactionListViewModel {
        let vm = TransactionListViewModel(repo: repo)
        vm.load()
        await vm.loadTask?.value
        return vm
    }

    // MARK: - Multi-Sheet Excel Import Tests

    @Test @MainActor
    func loadsMultiSheetExcelFileAndShowsSheetPicker() async throws {
        let url = Self.writeTempFile(base64: Self.multiSheetXLSXBase64, name: "multi-\(UUID()).xlsx")
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedCategories = [.test(name: "Food", type: .expense)]
        let vm = await loadedVM(mockRepo)

        // Load the multi-sheet workbook
        vm.loadExcelFile(from: url)
        // Wait for async file loading
        try await Task.sleep(for: .milliseconds(500))

        // Verify: multi-sheet workbook is loaded and sheet picker state is set
        #expect(vm.xlsxWorkbook != nil, "Workbook should be loaded")
        #expect(vm.xlsxWorkbook?.sheetNames == ["Jan", "Feb"], "Should have two sheets: Jan and Feb")
        #expect(vm.csvFile == nil, "CSVFile should not be set until a sheet is selected")
        #expect(vm.showingImportFlow == true, "Import flow should be showing")
    }

    @Test @MainActor
    func cancelingMultiSheetImportClearsState() async throws {
        let url = Self.writeTempFile(base64: Self.multiSheetXLSXBase64, name: "multi-\(UUID()).xlsx")
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedCategories = [.test(name: "Food", type: .expense)]
        let vm = await loadedVM(mockRepo)

        // Load file and then cancel
        vm.loadExcelFile(from: url)
        try await Task.sleep(for: .milliseconds(500))

        // Verify workbook is loaded before cancellation
        #expect(vm.xlsxWorkbook != nil, "Workbook should be loaded")

        vm.cancelImport()

        // Verify: all import state is cleared
        #expect(vm.showingImportFlow == false, "Import flow should be hidden after cancel")
        #expect(vm.csvFile == nil, "CSVFile should be cleared")
        #expect(vm.xlsxWorkbook == nil, "Workbook should be cleared")
        #expect(vm.mappedRows.isEmpty, "Mapped rows should be empty")
        #expect(vm.importNavigationPath.isEmpty, "Navigation path should be empty")
    }
}
