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
    // ponytail: uses ZIP_STORED (no compression) — see XLSXWorkbookTests.swift
    // for why (a DEFLATE-specific fixture-generation quirk, not a production bug).
    static let multiSheetXLSXBase64 = """
    UEsDBBQAAAAAAAAAIQA3p7O+zwMAAM8DAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbDw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rp
    bmc9IlVURi04IiBzdGFuZGFsb25lPSJ5ZXMiPz4KPFR5cGVzIHhtbG5zPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5v
    cmcvcGFja2FnZS8yMDA2L2NvbnRlbnQtdHlwZXMiPgogIDxEZWZhdWx0IEV4dGVuc2lvbj0icmVscyIgQ29udGVudFR5cGU9ImFw
    cGxpY2F0aW9uL3ZuZC5vcGVueG1sZm9ybWF0cy1wYWNrYWdlLnJlbGF0aW9uc2hpcHMreG1sIi8+CiAgPERlZmF1bHQgRXh0ZW5z
    aW9uPSJ4bWwiIENvbnRlbnRUeXBlPSJhcHBsaWNhdGlvbi94bWwiLz4KICA8T3ZlcnJpZGUgUGFydE5hbWU9Ii94bC93b3JrYm9v
    ay54bWwiIENvbnRlbnRUeXBlPSJhcHBsaWNhdGlvbi92bmQub3BlbnhtbGZvcm1hdHMtb2ZmaWNlZG9jdW1lbnQuc3ByZWFkc2hl
    ZXRtbC5zaGVldC5tYWluK3htbCIvPgogIDxPdmVycmlkZSBQYXJ0TmFtZT0iL3hsL3dvcmtzaGVldHMvc2hlZXQxLnhtbCIgQ29u
    dGVudFR5cGU9ImFwcGxpY2F0aW9uL3ZuZC5vcGVueG1sZm9ybWF0cy1vZmZpY2Vkb2N1bWVudC5zcHJlYWRzaGVldG1sLndvcmtz
    aGVldCt4bWwiLz4KICA8T3ZlcnJpZGUgUGFydE5hbWU9Ii94bC93b3Jrc2hlZXRzL3NoZWV0Mi54bWwiIENvbnRlbnRUeXBlPSJh
    cHBsaWNhdGlvbi92bmQub3BlbnhtbGZvcm1hdHMtb2ZmaWNlZG9jdW1lbnQuc3ByZWFkc2hlZXRtbC53b3Jrc2hlZXQreG1sIi8+
    CiAgPE92ZXJyaWRlIFBhcnROYW1lPSIveGwvc3R5bGVzLnhtbCIgQ29udGVudFR5cGU9ImFwcGxpY2F0aW9uL3ZuZC5vcGVueG1s
    Zm9ybWF0cy1vZmZpY2Vkb2N1bWVudC5zcHJlYWRzaGVldG1sLnN0eWxlcyt4bWwiLz4KICA8T3ZlcnJpZGUgUGFydE5hbWU9Ii94
    bC9zaGFyZWRTdHJpbmdzLnhtbCIgQ29udGVudFR5cGU9ImFwcGxpY2F0aW9uL3ZuZC5vcGVueG1sZm9ybWF0cy1vZmZpY2Vkb2N1
    bWVudC5zcHJlYWRzaGVldG1sLnNoYXJlZFN0cmluZ3MreG1sIi8+CjwvVHlwZXM+ClBLAwQUAAAAAAAAACEAXd8jJy0BAAAtAQAA
    CwAAAF9yZWxzLy5yZWxzPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9InllcyI/Pgo8UmVs
    YXRpb25zaGlwcyB4bWxucz0iaHR0cDovL3NjaGVtYXMub3BlbnhtbGZvcm1hdHMub3JnL3BhY2thZ2UvMjAwNi9yZWxhdGlvbnNo
    aXBzIj4KICA8UmVsYXRpb25zaGlwIElkPSJySWQxIiBUeXBlPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5vcmcvb2Zm
    aWNlRG9jdW1lbnQvMjAwNi9yZWxhdGlvbnNoaXBzL29mZmljZURvY3VtZW50IiBUYXJnZXQ9InhsL3dvcmtib29rLnhtbCIvPgo8
    L1JlbGF0aW9uc2hpcHM+ClBLAwQUAAAAAAAAACEAR1GIJlYBAABWAQAADwAAAHhsL3dvcmtib29rLnhtbDw/eG1sIHZlcnNpb249
    IjEuMCIgZW5jb2Rpbmc9IlVURi04IiBzdGFuZGFsb25lPSJ5ZXMiPz4KPHdvcmtib29rIHhtbG5zPSJodHRwOi8vc2NoZW1hcy5v
    cGVueG1sZm9ybWF0cy5vcmcvc3ByZWFkc2hlZXRtbC8yMDA2L21haW4iIHhtbG5zOnI9Imh0dHA6Ly9zY2hlbWFzLm9wZW54bWxm
    b3JtYXRzLm9yZy9vZmZpY2VEb2N1bWVudC8yMDA2L3JlbGF0aW9uc2hpcHMiPgogIDxzaGVldHM+CiAgICA8c2hlZXQgbmFtZT0i
    SmFuIiBzaGVldElkPSIxIiByOmlkPSJySWQxIi8+CiAgICA8c2hlZXQgbmFtZT0iRmViIiBzaGVldElkPSIyIiByOmlkPSJySWQy
    Ii8+CiAgPC9zaGVldHM+Cjwvd29ya2Jvb2s+ClBLAwQUAAAAAAAAACEAlIztBdACAADQAgAAGgAAAHhsL19yZWxzL3dvcmtib29r
    LnhtbC5yZWxzPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9InllcyI/Pgo8UmVsYXRpb25z
    aGlwcyB4bWxucz0iaHR0cDovL3NjaGVtYXMub3BlbnhtbGZvcm1hdHMub3JnL3BhY2thZ2UvMjAwNi9yZWxhdGlvbnNoaXBzIj4K
    ICA8UmVsYXRpb25zaGlwIElkPSJySWQxIiBUeXBlPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5vcmcvb2ZmaWNlRG9j
    dW1lbnQvMjAwNi9yZWxhdGlvbnNoaXBzL3dvcmtzaGVldCIgVGFyZ2V0PSJ3b3Jrc2hlZXRzL3NoZWV0MS54bWwiLz4KICA8UmVs
    YXRpb25zaGlwIElkPSJySWQyIiBUeXBlPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5vcmcvb2ZmaWNlRG9jdW1lbnQv
    MjAwNi9yZWxhdGlvbnNoaXBzL3dvcmtzaGVldCIgVGFyZ2V0PSJ3b3Jrc2hlZXRzL3NoZWV0Mi54bWwiLz4KICA8UmVsYXRpb25z
    aGlwIElkPSJySWQzIiBUeXBlPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5vcmcvb2ZmaWNlRG9jdW1lbnQvMjAwNi9y
    ZWxhdGlvbnNoaXBzL3N0eWxlcyIgVGFyZ2V0PSJzdHlsZXMueG1sIi8+CiAgPFJlbGF0aW9uc2hpcCBJZD0icklkNCIgVHlwZT0i
    aHR0cDovL3NjaGVtYXMub3BlbnhtbGZvcm1hdHMub3JnL29mZmljZURvY3VtZW50LzIwMDYvcmVsYXRpb25zaGlwcy9zaGFyZWRT
    dHJpbmdzIiBUYXJnZXQ9InNoYXJlZFN0cmluZ3MueG1sIi8+CjwvUmVsYXRpb25zaGlwcz4KUEsDBBQAAAAAAAAAIQADWZ4fSgIA
    AEoCAAANAAAAeGwvc3R5bGVzLnhtbDw/eG1sIHZlcnNpb249IjEuMCIgZW5jb2Rpbmc9IlVURi04IiBzdGFuZGFsb25lPSJ5ZXMi
    Pz4KPHN0eWxlU2hlZXQgeG1sbnM9Imh0dHA6Ly9zY2hlbWFzLm9wZW54bWxmb3JtYXRzLm9yZy9zcHJlYWRzaGVldG1sLzIwMDYv
    bWFpbiI+CiAgPGZvbnRzIGNvdW50PSIxIj48Zm9udD48c3ogdmFsPSIxMSIvPjxuYW1lIHZhbD0iQ2FsaWJyaSIvPjwvZm9udD48
    L2ZvbnRzPgogIDxmaWxscyBjb3VudD0iMSI+PGZpbGw+PHBhdHRlcm5GaWxsIHBhdHRlcm5UeXBlPSJub25lIi8+PC9maWxsPjwv
    ZmlsbHM+CiAgPGJvcmRlcnMgY291bnQ9IjEiPjxib3JkZXI+PGxlZnQvPjxyaWdodC8+PHRvcC8+PGJvdHRvbS8+PGRpYWdvbmFs
    Lz48L2JvcmRlcj48L2JvcmRlcnM+CiAgPGNlbGxTdHlsZVhmcyBjb3VudD0iMSI+PHhmIG51bUZtdElkPSIwIiBmb250SWQ9IjAi
    IGZpbGxJZD0iMCIgYm9yZGVySWQ9IjAiLz48L2NlbGxTdHlsZVhmcz4KICA8Y2VsbFhmcyBjb3VudD0iMSI+CiAgICA8eGYgbnVt
    Rm10SWQ9IjAiIGZvbnRJZD0iMCIgZmlsbElkPSIwIiBib3JkZXJJZD0iMCIgeGZJZD0iMCIvPgogIDwvY2VsbFhmcz4KPC9zdHls
    ZVNoZWV0PgpQSwMEFAAAAAAAAAAhAKclAb4QAQAAEAEAABQAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbDw/eG1sIHZlcnNpb249IjEu
    MCIgZW5jb2Rpbmc9IlVURi04IiBzdGFuZGFsb25lPSJ5ZXMiPz4KPHNzdCB4bWxucz0iaHR0cDovL3NjaGVtYXMub3BlbnhtbGZv
    cm1hdHMub3JnL3NwcmVhZHNoZWV0bWwvMjAwNi9tYWluIiBjb3VudD0iNCIgdW5pcXVlQ291bnQ9IjQiPgogIDxzaT48dD5Ob3Rl
    PC90Pjwvc2k+CiAgPHNpPjx0PkphbnVhcnkgZW50cnk8L3Q+PC9zaT4KICA8c2k+PHQ+Tm90ZTwvdD48L3NpPgogIDxzaT48dD5G
    ZWJydWFyeSBlbnRyeTwvdD48L3NpPgo8L3NzdD4KUEsDBBQAAAAAAAAAIQA6qqQeFAEAABQBAAAYAAAAeGwvd29ya3NoZWV0cy9z
    aGVldDEueG1sPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9InllcyI/Pgo8d29ya3NoZWV0
    IHhtbG5zPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5vcmcvc3ByZWFkc2hlZXRtbC8yMDA2L21haW4iPgogIDxzaGVl
    dERhdGE+CiAgICA8cm93IHI9IjEiPjxjIHI9IkExIiB0PSJzIj48dj4wPC92PjwvYz48L3Jvdz4KICAgIDxyb3cgcj0iMiI+PGMg
    cj0iQTIiIHQ9InMiPjx2PjE8L3Y+PC9jPjwvcm93PgogIDwvc2hlZXREYXRhPgo8L3dvcmtzaGVldD4KUEsDBBQAAAAAAAAAIQBK
    F4CCFAEAABQBAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDIueG1sPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgi
    IHN0YW5kYWxvbmU9InllcyI/Pgo8d29ya3NoZWV0IHhtbG5zPSJodHRwOi8vc2NoZW1hcy5vcGVueG1sZm9ybWF0cy5vcmcvc3By
    ZWFkc2hlZXRtbC8yMDA2L21haW4iPgogIDxzaGVldERhdGE+CiAgICA8cm93IHI9IjEiPjxjIHI9IkExIiB0PSJzIj48dj4yPC92
    PjwvYz48L3Jvdz4KICAgIDxyb3cgcj0iMiI+PGMgcj0iQTIiIHQ9InMiPjx2PjM8L3Y+PC9jPjwvcm93PgogIDwvc2hlZXREYXRh
    Pgo8L3dvcmtzaGVldD4KUEsBAhQDFAAAAAAAAAAhADens77PAwAAzwMAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVz
    XS54bWxQSwECFAMUAAAAAAAAACEAXd8jJy0BAAAtAQAACwAAAAAAAAAAAAAAgAEABAAAX3JlbHMvLnJlbHNQSwECFAMUAAAAAAAA
    ACEAR1GIJlYBAABWAQAADwAAAAAAAAAAAAAAgAFWBQAAeGwvd29ya2Jvb2sueG1sUEsBAhQDFAAAAAAAAAAhAJSM7QXQAgAA0AIA
    ABoAAAAAAAAAAAAAAIAB2QYAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzUEsBAhQDFAAAAAAAAAAhAANZnh9KAgAASgIAAA0A
    AAAAAAAAAAAAAIAB4QkAAHhsL3N0eWxlcy54bWxQSwECFAMUAAAAAAAAACEApyUBvhABAAAQAQAAFAAAAAAAAAAAAAAAgAFWDAAA
    eGwvc2hhcmVkU3RyaW5ncy54bWxQSwECFAMUAAAAAAAAACEAOqqkHhQBAAAUAQAAGAAAAAAAAAAAAAAAgAGYDQAAeGwvd29ya3No
    ZWV0cy9zaGVldDEueG1sUEsBAhQDFAAAAAAAAAAhAEoXgIIUAQAAFAEAABgAAAAAAAAAAAAAAIAB4g4AAHhsL3dvcmtzaGVldHMv
    c2hlZXQyLnhtbFBLBQYAAAAACAAIAAgCAAAsEAAAAAA=
    """

    // Single-sheet Excel fixture (same as XLSXWorkbookTests.sampleXLSXBase64).
    // Sheet "Transactions": headers Date/Amount/Note, two data rows
    // (2026-01-05, -42.5, "Groceries") and (2026-03-15, 1500, "Salary").
    static let sampleXLSXBase64 = """
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

        vm.loadExcelFile(from: url)
        await vm.loadExcelTask?.value

        // Verify: multi-sheet workbook is loaded and sheet picker state is set
        #expect(vm.xlsxWorkbook != nil, "Workbook should be loaded")
        #expect(vm.xlsxWorkbook?.sheetNames == ["Jan", "Feb"], "Should have two sheets: Jan and Feb")
        #expect(vm.csvFile == nil, "CSVFile should not be set until a sheet is selected")
        #expect(vm.showingImportFlow == true, "Import flow should be showing")
    }

    @Test @MainActor
    func selectingSheetPopulatesCSVFileAndColumnMapping() async throws {
        let url = Self.writeTempFile(base64: Self.multiSheetXLSXBase64, name: "multi-\(UUID()).xlsx")
        let mockRepo = MockTransactionRepository()
        let vm = await loadedVM(mockRepo)

        vm.loadExcelFile(from: url)
        await vm.loadExcelTask?.value
        #expect(vm.xlsxWorkbook?.sheetNames == ["Jan", "Feb"])

        vm.selectSheet("Feb")

        #expect(vm.xlsxWorkbook == nil, "Workbook selection state should be cleared once a sheet is chosen")
        #expect(vm.csvFile?.headers == ["Note"])
        var rows: [[String]] = []
        vm.csvFile?.processRows { rows.append($0) }
        #expect(rows == [["February entry"]], "Should convert the chosen sheet's own rows, not the other sheet's")

        // Column mapping auto-detect ran on the selected sheet: this fixture only
        // has a "Note" column, so it should be recognized as the note column and
        // nothing else should be guessed.
        #expect(vm.columnMapping.noteColumn == "Note")
        #expect(vm.columnMapping.dateColumn == nil)
        #expect(vm.columnMapping.amountColumn == nil)
    }

    @Test @MainActor
    func cancelingMultiSheetImportClearsState() async throws {
        let url = Self.writeTempFile(base64: Self.multiSheetXLSXBase64, name: "multi-\(UUID()).xlsx")
        let mockRepo = MockTransactionRepository()
        mockRepo.stubbedCategories = [.test(name: "Food", type: .expense)]
        let vm = await loadedVM(mockRepo)

        vm.loadExcelFile(from: url)
        await vm.loadExcelTask?.value
        #expect(vm.xlsxWorkbook != nil, "Workbook should be loaded")

        vm.cancelImport()

        // Verify: all import state is cleared
        #expect(vm.showingImportFlow == false, "Import flow should be hidden after cancel")
        #expect(vm.csvFile == nil, "CSVFile should be cleared")
        #expect(vm.xlsxWorkbook == nil, "Workbook should be cleared")
        #expect(vm.mappedRows.isEmpty, "Mapped rows should be empty")
        #expect(vm.importNavigationPath.isEmpty, "Navigation path should be empty")
    }

    // MARK: - Single-Sheet Excel Import: Full Pipeline

    @Test @MainActor
    func singleSheetWorkbookAutoSelectsAndMapsRowsCorrectly() async throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let mockRepo = MockTransactionRepository()
        let vm = await loadedVM(mockRepo)

        // Single-sheet workbooks skip the picker entirely
        vm.loadExcelFile(from: url)
        await vm.loadExcelTask?.value

        #expect(vm.xlsxWorkbook == nil, "Single-sheet workbook should auto-select, no picker state")
        #expect(vm.csvFile?.headers == ["Date", "Amount", "Note"])
        #expect(vm.columnMapping.dateColumn == "Date", "Auto-detect should find the Date column")
        #expect(vm.columnMapping.amountColumn == "Amount", "Auto-detect should find the Amount column")

        await vm.applyMapping()

        #expect(vm.mappedRows.count == 2)
        let inputs = vm.mappedRows.compactMap(\.input)
        #expect(inputs.count == 2, "Both Excel-sourced rows should map without error")
        #expect(inputs[0].amount == -42.5)
        #expect(inputs[0].note == "Groceries")
        #expect(inputs[1].amount == 1500)
        #expect(inputs[1].note == "Salary")
    }
}
