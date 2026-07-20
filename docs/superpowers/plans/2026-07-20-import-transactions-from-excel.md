# Import Transactions from Excel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users import transactions from an `.xlsx` file, with the same "auto-detect the format, only ask when unsure" experience the existing CSV import already provides.

**Architecture:** Add a CoreXLSX-backed reader (`XLSXWorkbook`) that converts a chosen worksheet into the app's existing `CSVFile` value type. Everything downstream — `CSVColumnMapper.autoDetect`, `CSVColumnMappingView`, `CSVCategoryMappingView`, duplicate detection, category resolution — is reused completely unchanged.

**Tech Stack:** Swift, SwiftUI, SwiftData, Swift Testing (`@Test`/`#expect`), CoreXLSX (new SPM dependency, pulls in XMLCoder and ZIPFoundation transitively).

## Global Constraints

- Build/test only via Xcode MCP tools (`mcp__xcode__BuildProject`, `mcp__xcode__RunAllTests`, `mcp__xcode__RunSomeTests`) with `tabIdentifier: "windowtab1"`. Never run `xcodebuild` or call MCP tool names as Bash commands. Load their schemas first via `ToolSearch` with `query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"`.
- Swift Testing (`@Test`, `#expect`), not XCTest; test files use `@testable import PersonalFinanceTraker`.
- Amounts are stored as negative `Decimal` for expenses — not touched by this feature, cell-to-string conversion only.
- Directory is `PersonalFinanceTraker` (missing the 'c' in Tracker) — exact spelling matters for paths below.
- Only the first sheet's cell values are read canonically (raw value, not Excel's display format) — dates convert to `yyyy-MM-dd HH:mm:ss`, numbers to plain decimal text.
- Out of scope (do not build): legacy binary `.xls`, password-protected files, per-cause error messages, custom/locale date-format detection beyond Excel's built-in numFmtIds 14–22 and 45–47.

---

## File Structure

- **Create** `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift` — CoreXLSX-backed reader; converts a worksheet into a `CSVFile`.
- **Create** `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/SheetPickerView.swift` — sheet-selection screen, shown only for multi-sheet workbooks.
- **Create** `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift` — unit tests for the reader.
- **Modify** `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVImportService.swift` — extract a `dedupeHeaders` helper so `XLSXWorkbook` can reuse the existing header-deduplication logic instead of re-implementing it.
- **Modify** `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift` — add `xlsxWorkbook` state, `loadExcelFile(from:)`, `selectSheet(_:)`; reset new state in `cancelImport()`.
- **Modify** `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/ImportFlowView.swift` — branch the flow's root view between `CSVColumnMappingView` (existing) and the new `SheetPickerView`.
- **Modify** `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift` — accept `.xlsx` in the file importer, route to `loadExcelFile`.
- **Modify** `PersonalFinanceTraker/PersonalFinanceTrakerUITests/` (existing UI test target — exact file found in Task 8) — add an end-to-end Excel import UI test.

---

### Task 1: Add the CoreXLSX SPM dependency

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj/project.pbxproj` (via Xcode GUI, not by hand-editing)

**Interfaces:**
- Produces: `import CoreXLSX` available to all targets that need it (main app target + unit test target).

There is no Xcode MCP tool for adding SPM package dependencies, so this step is manual:

- [ ] **Step 1: Add the package in Xcode**

Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` in Xcode. Go to **File → Add Package Dependencies…**, enter the URL:

```
https://github.com/CoreOffice/CoreXLSX.git
```

Choose **Up to Next Minor Version**, starting at `0.14.1`. When prompted which targets get the `CoreXLSX` product, add it to both `PersonalFinanceTraker` (the app target) and `PersonalFinanceTrakerTests` (the unit test target).

- [ ] **Step 2: Verify the project builds**

Load the tool schema, then build:

```
ToolSearch query: "select:mcp__xcode__BuildProject,mcp__xcode__RunAllTests,mcp__xcode__RunSomeTests"
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```

Expected: build succeeds (the dependency is fetched and linked, nothing references it yet so no new code runs).

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj/project.pbxproj PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "build: add CoreXLSX dependency for Excel import"
```

---

### Task 2: Extract a `dedupeHeaders` helper in `CSVImportService`

`XLSXWorkbook` needs the exact same "Accounts" → "Accounts", "Accounts_2" header-deduplication behavior `CSVImportService.parse` already has (`PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVImportService.swift:123-128`). Extract it into a reusable static function instead of duplicating the logic.

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVImportService.swift:123-128`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/CSVImportExportTests.swift`

**Interfaces:**
- Produces: `CSVImportService.dedupeHeaders(_ rawHeaders: [String]) -> [String]` — used by both `CSVImportService.parse` (Task 2) and `XLSXWorkbook.csvFile(forSheet:)` (Task 4).

- [ ] **Step 1: Write the failing test**

Add to `CSVImportServiceTests` in `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/CSVImportExportTests.swift`:

```swift
@Test func dedupeHeadersAppendsSuffixToRepeats() {
    let result = CSVImportService.dedupeHeaders(["Accounts", "Date", "Accounts", "Accounts"])
    #expect(result == ["Accounts", "Date", "Accounts_2", "Accounts_3"])
}

@Test func dedupeHeadersLeavesUniqueNamesUnchanged() {
    let result = CSVImportService.dedupeHeaders(["Date", "Amount", "Category"])
    #expect(result == ["Date", "Amount", "Category"])
}
```

- [ ] **Step 2: Run to verify it fails**

```
ToolSearch query: "select:mcp__xcode__RunSomeTests"
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["CSVImportServiceTests/dedupeHeadersAppendsSuffixToRepeats", "CSVImportServiceTests/dedupeHeadersLeavesUniqueNamesUnchanged"])
```

Expected: FAIL — `dedupeHeaders` does not exist yet (compile error).

- [ ] **Step 3: Extract the helper**

In `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVImportService.swift`, replace lines 123-128:

```swift
        var seen: [String: Int] = [:]
        let headers = rawHeaders.map { name -> String in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name)_\(count)"
        }
```

with:

```swift
        let headers = dedupeHeaders(rawHeaders)
```

and add this new static function to `CSVImportService` (near `parseRow`, e.g. right after `parse(_:)`):

```swift
    static func dedupeHeaders(_ rawHeaders: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return rawHeaders.map { name in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name)_\(count)"
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["CSVImportServiceTests/dedupeHeadersAppendsSuffixToRepeats", "CSVImportServiceTests/dedupeHeadersLeavesUniqueNamesUnchanged", "CSVImportServiceTests/parsesCommaDelimitedCSV"])
```

Expected: PASS (including the pre-existing `parsesCommaDelimitedCSV` test, confirming the refactor didn't change CSV behavior).

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVImportService.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/CSVImportExportTests.swift
git commit -m "refactor: extract dedupeHeaders helper for reuse by Excel import"
```

---

### Task 3: `XLSXWorkbook.read(from:)` and `sheetNames`

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift`
- Create: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift`

**Interfaces:**
- Consumes: `CSVFile(headers:delimiter:lines:)` from `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/CSVImportService.swift:15-19` (used starting Task 4).
- Produces:
  - `enum XLSXReadError: LocalizedError { case unreadable }`
  - `struct XLSXWorkbook { var sheetNames: [String] { get }; static func read(from url: URL) throws -> XLSXWorkbook; func csvFile(forSheet name: String) throws -> CSVFile }` — `read` and `sheetNames` are implemented in this task; `csvFile(forSheet:)` is implemented in Task 4 but must exist (even as a stub) for later tasks and tests to reference the type.

The test fixtures below are pre-verified, minimal, real `.xlsx` files (hand-built OOXML, validated with Python's `zipfile`/`xml.dom.minidom` — not third-party-library output) encoded as base64 so the test file is fully self-contained, with no bundle-resource wiring required:

- `sample.xlsx`: one sheet named "Transactions", headers `Date, Amount, Note`, two data rows. Column A is styled with numFmtId 14 (a built-in date format) — row 2 holds serial `46027` (2026-01-05), row 3 holds serial `46096` (2026-03-15), both verified against the Excel/OLE epoch (1899-12-30 + N days). Column B holds plain numbers (`-42.5`, `1500`). Column C holds shared-string text (`Groceries`, `Salary`).
- `multi-sheet.xlsx`: two sheets, "Jan" and "Feb", each with a one-column header (`Note`) and one data row.
- `corrupt.xlsx`: not a zip file at all — plain text bytes, for the unreadable-file case.

- [ ] **Step 1: Write the failing tests**

Create `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift`:

```swift
import Testing
import Foundation
@testable import PersonalFinanceTraker

struct XLSXWorkbookTests {

    // Minimal hand-built, pre-verified .xlsx fixtures (see plan doc for how they
    // were generated and validated). Written to a temp file per test because
    // XLSXWorkbook.read(from:) takes a URL.
    static let sampleXLSXBase64 = """
    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
    """

    static let multiSheetXLSXBase64 = """
    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
    """

    static func writeTempFile(base64: String, name: String) -> URL {
        let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    @Test func readsSingleSheetName() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        #expect(workbook.sheetNames == ["Transactions"])
    }

    @Test func readsMultipleSheetNames() throws {
        let url = Self.writeTempFile(base64: Self.multiSheetXLSXBase64, name: "multi-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        #expect(workbook.sheetNames == ["Jan", "Feb"])
    }

    @Test func corruptFileThrowsUnreadable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID()).xlsx")
        try! "not a zip file".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: XLSXReadError.unreadable) {
            try XLSXWorkbook.read(from: url)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["XLSXWorkbookTests"])
```

Expected: FAIL — `XLSXWorkbook` does not exist yet (compile error).

- [ ] **Step 3: Implement `XLSXWorkbook.read` and `sheetNames`**

Create `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift`:

```swift
//
//  XLSXWorkbook.swift
//  PersonalFinanceTraker
//

import Foundation
import CoreXLSX

enum XLSXReadError: LocalizedError, Equatable {
    case unreadable

    var errorDescription: String? {
        "Couldn't read this file — make sure it's a valid, unprotected .xlsx."
    }
}

/// Adapts a parsed .xlsx workbook into the existing CSVFile pipeline, so
/// CSVColumnMapper / CSVColumnMappingView / CSVCategoryMappingView work
/// unchanged regardless of whether the source was a CSV or an Excel file.
struct XLSXWorkbook {
    private let file: XLSXFile
    private let styles: Styles
    private let sharedStrings: SharedStrings?
    private let sheets: [(name: String, path: String)]

    var sheetNames: [String] { sheets.map(\.name) }

    static func read(from url: URL) throws -> XLSXWorkbook {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let coreFile = try? XLSXFile(data: data) else {
            throw XLSXReadError.unreadable
        }
        guard let workbook = try? coreFile.parseWorkbooks().first,
              let pathsAndNames = try? coreFile.parseWorksheetPathsAndNames(workbook: workbook),
              !pathsAndNames.isEmpty else {
            throw XLSXReadError.unreadable
        }
        guard let styles = try? coreFile.parseStyles() else {
            throw XLSXReadError.unreadable
        }
        let sharedStrings = try? coreFile.parseSharedStrings()

        let sheets = pathsAndNames.enumerated().map { idx, entry in
            (name: entry.name ?? "Sheet \(idx + 1)", path: entry.path)
        }

        return XLSXWorkbook(file: coreFile, styles: styles, sharedStrings: sharedStrings, sheets: sheets)
    }

    /// Implemented in the next task.
    func csvFile(forSheet name: String) throws -> CSVFile {
        throw XLSXReadError.unreadable
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["XLSXWorkbookTests"])
```

Expected: PASS for `readsSingleSheetName`, `readsMultipleSheetNames`, `corruptFileThrowsUnreadable`.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift
git commit -m "feat: read xlsx workbooks and list their sheet names"
```

---

### Task 4: `XLSXWorkbook.csvFile(forSheet:)` — cell conversion

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift`
- Test: `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift`

**Interfaces:**
- Consumes: `CSVImportService.dedupeHeaders(_ rawHeaders: [String]) -> [String]` (Task 2); `CSVFile(headers:delimiter:lines:)` (existing, `CSVImportService.swift:15-19`); `CSVFile.processRows`, `.preview`, `.columnIndex(for:)` (existing, used implicitly by downstream `CSVColumnMapper` — not called directly here).
- Produces: `XLSXWorkbook.csvFile(forSheet name: String) throws -> CSVFile` — the shape downstream `CSVColumnMapper.autoDetect(from:)` (Task 6) consumes.

- [ ] **Step 1: Write the failing tests**

Add to `XLSXWorkbookTests` in `PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift`:

```swift
    @Test func convertsHeaderRowAndDataRows() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        let file = try workbook.csvFile(forSheet: "Transactions")
        #expect(file.headers == ["Date", "Amount", "Note"])
        #expect(file.rowCount == 2)
    }

    @Test func convertsDateCellsToCanonicalISOStrings() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        let file = try workbook.csvFile(forSheet: "Transactions")
        var dates: [String] = []
        file.processRows { row in dates.append(row[0]) }
        // Serials 46027 / 46096 verified against the Excel/OLE epoch (1899-12-30 + N days)
        #expect(dates == ["2026-01-05 00:00:00", "2026-03-15 00:00:00"])
    }

    @Test func convertsNumberAndStringCellsAsPlainText() throws {
        let url = Self.writeTempFile(base64: Self.sampleXLSXBase64, name: "sample-\(UUID()).xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        let file = try workbook.csvFile(forSheet: "Transactions")
        var amounts: [String] = []
        var notes: [String] = []
        file.processRows { row in
            amounts.append(row[1])
            notes.append(row[2])
        }
        #expect(amounts == ["-42.5", "1500"])
        #expect(notes == ["Groceries", "Salary"])
    }

    @Test func isDateNumberFormatMatchesBuiltInDateAndTimeIds() {
        #expect(XLSXWorkbook.isDateNumberFormat(14))
        #expect(XLSXWorkbook.isDateNumberFormat(22))
        #expect(XLSXWorkbook.isDateNumberFormat(46))
        #expect(!XLSXWorkbook.isDateNumberFormat(0))
        #expect(!XLSXWorkbook.isDateNumberFormat(9))
        #expect(!XLSXWorkbook.isDateNumberFormat(164))
    }
```

- [ ] **Step 2: Run to verify it fails**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["XLSXWorkbookTests/convertsHeaderRowAndDataRows", "XLSXWorkbookTests/convertsDateCellsToCanonicalISOStrings", "XLSXWorkbookTests/convertsNumberAndStringCellsAsPlainText", "XLSXWorkbookTests/isDateNumberFormatMatchesBuiltInDateAndTimeIds"])
```

Expected: FAIL — `csvFile(forSheet:)` still throws a stub error; `isDateNumberFormat` doesn't exist.

- [ ] **Step 3: Implement cell conversion**

Replace the stub `csvFile(forSheet:)` in `PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift` and add the private helpers below it (inside `struct XLSXWorkbook`, after `read(from:)`):

```swift
    /// Converts one worksheet into a CSVFile: first row becomes headers, the
    /// rest become CSVFile's raw lines, joined with a control-character
    /// delimiter that real spreadsheet text never contains — so CSVFile's own
    /// lazy row parsing (built for comma/semicolon/tab CSV text) works
    /// unmodified on Excel-sourced rows without needing CSV-style escaping.
    func csvFile(forSheet name: String) throws -> CSVFile {
        guard let sheet = sheets.first(where: { $0.name == name }),
              let worksheet = try? file.parseWorksheet(at: sheet.path) else {
            throw XLSXReadError.unreadable
        }
        let rows = worksheet.data?.rows ?? []
        guard let headerRow = rows.first else {
            return CSVFile(headers: [], delimiter: Self.delimiter, lines: [])
        }

        let columnCount = rows
            .flatMap(\.cells)
            .map { $0.reference.column.intValue }
            .max() ?? 0

        let rawHeaders = fields(for: headerRow, columnCount: columnCount)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let headers = CSVImportService.dedupeHeaders(rawHeaders)

        let dataLines: [(lineNumber: Int, text: String)] = rows.dropFirst().enumerated().map { idx, row in
            let text = fields(for: row, columnCount: columnCount).joined(separator: String(Self.delimiter))
            return (lineNumber: idx + 2, text: text)
        }

        return CSVFile(headers: headers, delimiter: Self.delimiter, lines: dataLines)
    }

    // Control character (Unit Separator) instead of a printable delimiter —
    // spreadsheet cell text realistically never contains it, so no CSV-style
    // quoting/escaping is needed when re-serializing cells into CSVFile's raw-line format.
    private static let delimiter: Character = "\u{1F}"

    private func fields(for row: Row, columnCount: Int) -> [String] {
        var result = Array(repeating: "", count: columnCount)
        for cell in row.cells {
            let idx = cell.reference.column.intValue - 1
            guard idx >= 0, idx < columnCount else { continue }
            result[idx] = stringify(cell)
        }
        return result
    }

    private func stringify(_ cell: Cell) -> String {
        let numFmtId = cell.format(in: styles)?.numberFormatId ?? 0
        if Self.isDateNumberFormat(numFmtId), let raw = cell.value, let serial = Double(raw) {
            return Self.canonicalDateString(fromSerial: serial)
        }
        if cell.type == .sharedString {
            return sharedStrings.flatMap { cell.stringValue($0) } ?? ""
        }
        return cell.value ?? ""
    }

    // ponytail: only the built-in date/time numFmtIds Excel assigns
    // automatically (14-22 dates/times, 45-47 mm:ss variants). Custom,
    // locale-specific date formats (numFmtId >= 164) aren't detected — extend
    // this if a real-world export needs it.
    static func isDateNumberFormat(_ id: Int) -> Bool {
        (14...22).contains(id) || (45...47).contains(id)
    }

    private static let canonicalDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // Excel/OLE Automation date system: day 0 = 1899-12-30 (this already
    // accounts for Excel's fictitious Feb 29, 1900 for any date after that,
    // which is the de facto standard virtually every spreadsheet tool follows).
    private static let excelEpoch: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
    }()

    private static func canonicalDateString(fromSerial serial: Double) -> String {
        let date = excelEpoch.addingTimeInterval(serial * 86400)
        return canonicalDateFormatter.string(from: date)
    }
```

- [ ] **Step 4: Run to verify it passes**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["XLSXWorkbookTests"])
```

Expected: PASS for all `XLSXWorkbookTests`.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Utilities/XLSXWorkbook.swift PersonalFinanceTraker/PersonalFinanceTrakerTests/Utilities/XLSXWorkbookTests.swift
git commit -m "feat: convert xlsx worksheet cells into CSVFile rows"
```

---

### Task 5: `SheetPickerView`

**Files:**
- Create: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/SheetPickerView.swift`

**Interfaces:**
- Produces: `struct SheetPickerView: View { let sheetNames: [String]; let onSelect: (String) -> Void; let onCancel: () -> Void }` — used by `ImportFlowView` (Task 6).

This is a simple SwiftUI view with no non-trivial logic (a picker list), so per the plan's task-sizing guidance it needs no separate unit test — it's exercised by the Task 8 UI test.

- [ ] **Step 1: Create the view**

```swift
//
//  SheetPickerView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct SheetPickerView: View {
    let sheetNames: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        List(sheetNames, id: \.self) { name in
            Button {
                onSelect(name)
            } label: {
                HStack {
                    Text(name)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
        }
        .navigationTitle("Choose a Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```

Expected: build succeeds (the view isn't referenced anywhere yet, so this only checks it compiles standalone).

- [ ] **Step 3: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/SheetPickerView.swift
git commit -m "feat: add sheet picker view for multi-sheet Excel imports"
```

---

### Task 6: Wire `XLSXWorkbook` into `TransactionListViewModel` and `ImportFlowView`

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift:285-343`
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/ImportFlowView.swift`

**Interfaces:**
- Consumes: `XLSXWorkbook.read(from:) throws -> XLSXWorkbook`, `.sheetNames: [String]`, `.csvFile(forSheet:) throws -> CSVFile` (Tasks 3-4); `SheetPickerView` (Task 5); existing `CSVColumnMapper.autoDetect(from:)`, `CSVColumnMappingView`.
- Produces: `TransactionListViewModel.loadExcelFile(from url: URL)`, `TransactionListViewModel.selectSheet(_ name: String)`, `TransactionListViewModel.xlsxWorkbook: XLSXWorkbook?` — used by `ProfileView` (Task 7).

This task has no new pure logic to unit test in isolation (it's state wiring + navigation branching); it's verified end-to-end by the Task 8 UI test. Implement directly, then verify the project still builds and existing CSV import tests still pass (regression check, since `cancelImport` is touched).

- [ ] **Step 1: Add Excel state and methods to `TransactionListViewModel`**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift`, add a new property next to `csvFile` (after line 287, `var csvFile: CSVFile? = nil`):

```swift
    var xlsxWorkbook: XLSXWorkbook? = nil
```

Add these two methods right after `loadCSVFile(from:)` (after its closing brace, currently line 328):

```swift
    func loadExcelFile(from url: URL) {
        isLoadingCSV = true
        Task {
            do {
                let workbook = try await Task.detached(priority: .userInitiated) {
                    try XLSXWorkbook.read(from: url)
                }.value
                isLoadingCSV = false
                availableCategories = try await repo.fetchCategories()
                categoryResolutionSelections = [:]
                csvCategories = []
                csvCategoryTypes = [:]
                importNavigationPath = []
                hasAutoMappedCategories = false

                if workbook.sheetNames.count == 1, let onlySheet = workbook.sheetNames.first {
                    try applySheet(onlySheet, of: workbook)
                    xlsxWorkbook = nil
                } else {
                    xlsxWorkbook = workbook
                    csvFile = nil
                }
                showingImportFlow = true
            } catch {
                isLoadingCSV = false
                importError = error.localizedDescription
            }
        }
    }

    func selectSheet(_ name: String) {
        guard let workbook = xlsxWorkbook else { return }
        do {
            try applySheet(name, of: workbook)
            xlsxWorkbook = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func applySheet(_ name: String, of workbook: XLSXWorkbook) throws {
        let file = try workbook.csvFile(forSheet: name)
        csvFile = file
        columnMapping = CSVColumnMapper.autoDetect(from: file)
        columnMapping.defaultCurrency = currencyService.baseCurrency
    }
```

Add `xlsxWorkbook = nil` to `cancelImport()` (currently `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift:331-343`), right after `csvFile = nil`:

```swift
        csvFile = nil
        xlsxWorkbook = nil
```

- [ ] **Step 2: Branch `ImportFlowView`'s root on `xlsxWorkbook`**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/ImportFlowView.swift`, replace the `if let file = viewModel.csvFile { ... }` block (lines 17-53) with:

```swift
            if let file = viewModel.csvFile {
                CSVColumnMappingView(
                    file: file,
                    mapping: $viewModel.columnMapping,
                    currentStep: 1,
                    totalSteps: totalSteps,
                    onContinue: { handleColumnMappingContinue() },
                    onCancel: { viewModel.cancelImport() }
                )
                .navigationDestination(for: ImportStep.self) { step in
                    switch step {
                    case .categoryMapping:
                        CSVCategoryMappingView(
                            csvCategories: viewModel.csvCategories,
                            categoryTypes: viewModel.csvCategoryTypes,
                            availableCategories: viewModel.availableCategories,
                            selections: $viewModel.categoryResolutionSelections,
                            currentStep: 2,
                            totalSteps: totalSteps,
                            onContinue: {
                                Task {
                                    await viewModel.applyMapping()
                                    viewModel.importNavigationPath.append(.results)
                                }
                            }
                        )
                    case .results:
                        ImportResultView(
                            rows: viewModel.mappedRows,
                            isImporting: viewModel.isImporting,
                            currentStep: totalSteps,
                            totalSteps: totalSteps,
                            onConfirm: { viewModel.confirmImport($0) }
                        )
                    }
                }
            } else if let workbook = viewModel.xlsxWorkbook {
                SheetPickerView(
                    sheetNames: workbook.sheetNames,
                    onSelect: { viewModel.selectSheet($0) },
                    onCancel: { viewModel.cancelImport() }
                )
            }
```

(Only the root `if`/`else if` changed; `handleColumnMappingContinue()` is untouched.)

- [ ] **Step 3: Verify it builds and existing CSV tests still pass**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["CSVImportServiceTests", "CSVColumnMapperTests"])
```

Expected: build succeeds; all CSV tests still PASS (confirms the CSV path — `viewModel.csvFile != nil` — is unaffected by the added `else if` branch).

- [ ] **Step 4: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/TransactionListViewModel.swift PersonalFinanceTraker/PersonalFinanceTraker/Features/TransactionListView/Components/ImportFlowView.swift
git commit -m "feat: wire xlsx workbook loading and sheet selection into the import flow"
```

---

### Task 7: Accept `.xlsx` in `ProfileView`'s file importer

**Files:**
- Modify: `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift:1-2, 32-44, 79-90`

**Interfaces:**
- Consumes: `TransactionListViewModel.loadExcelFile(from:)`, `.loadCSVFile(from:)` (existing), `.isLoadingCSV` (existing).

- [ ] **Step 1: Add the `UniformTypeIdentifiers` import**

In `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift`, change lines 1-2 from:

```swift
import SwiftUI
import SwiftData
```

to:

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
```

- [ ] **Step 2: Update the button label**

Change line 42 from:

```swift
                                Label("Import CSV", systemImage: "square.and.arrow.down")
```

to:

```swift
                                Label("Import CSV or Excel", systemImage: "square.and.arrow.down")
```

- [ ] **Step 3: Accept `.xlsx` and route by extension**

Replace the `.fileImporter` block (currently lines 79-90):

```swift
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
```

with:

```swift
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
```

- [ ] **Step 4: Verify it builds**

```
mcp__xcode__BuildProject(tabIdentifier: "windowtab1")
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift
git commit -m "feat: accept .xlsx files in the import file picker"
```

---

### Task 8: End-to-end UI test

**Files:**
- Find the existing CSV import UI test first: run `mcp__xcode__XcodeGrep` (or `grep -rl "loadCSVFile\|Import CSV" PersonalFinanceTraker/PersonalFinanceTrakerUITests`) to locate it — mirror its exact structure (launch args, element queries, assertions) for the new test. If no CSV import UI test exists yet, add this as a new file `PersonalFinanceTraker/PersonalFinanceTrakerUITests/ExcelImportUITests.swift` following the same conventions as the other files in that directory (check one, e.g. via `mcp__xcode__XcodeGlob` on `PersonalFinanceTraker/PersonalFinanceTrakerUITests/*.swift`, for the launch/setup pattern this project uses).

**Interfaces:**
- Consumes: the full flow built in Tasks 1-7 (file picker → sheet picker for multi-sheet files → column mapping → category mapping → import).

- [ ] **Step 1: Locate existing UI test conventions**

```
ToolSearch query: "select:mcp__xcode__XcodeGlob,mcp__xcode__XcodeGrep,mcp__xcode__XcodeRead"
mcp__xcode__XcodeGlob(tabIdentifier: "windowtab1", pattern: "PersonalFinanceTraker/PersonalFinanceTrakerUITests/*.swift")
```

Read one or two of the resulting files with `mcp__xcode__XcodeRead` to see how this project launches the app under test, injects sample/seed data, and interacts with `fileImporter` (UI tests can't pick a real file from Files — check whether the existing CSV test seeds `TransactionListViewModel.csvFile`/`showingImportFlow` directly via a launch argument/environment hook, or drives the picker itself).

- [ ] **Step 2: Write the test**

Because the exact harness pattern (launch args vs. a debug-only deep-link vs. driving the system file picker) depends on what Step 1 finds, mirror that pattern exactly, but the assertions are fixed regardless of harness:

1. Trigger an Excel import using the `multi-sheet.xlsx`-equivalent fixture (two sheets) through whatever mechanism the existing CSV UI test uses to supply a file.
2. Assert a sheet-picker screen appears listing both sheet names ("Jan", "Feb" if reusing the same fixture content as Task 3, or the app's real sample data — match what the existing CSV test's fixture conventions use).
3. Tap one sheet name.
4. Assert the column mapping screen (`CSVColumnMappingView`, same screen the CSV test already asserts on) appears next.
5. Complete the flow the same way the existing CSV UI test does (continue → category mapping if applicable → results → confirm).
6. Assert the imported transaction(s) appear in the transaction list.

Write the concrete test code once Step 1's findings are known — do not guess the harness pattern.

- [ ] **Step 3: Run the UI test**

```
mcp__xcode__RunSomeTests(tabIdentifier: "windowtab1", testIdentifiers: ["<TestClassName>/<testMethodName>"])
```

Expected: PASS.

- [ ] **Step 4: Run the full test suite as a final regression check**

```
mcp__xcode__RunAllTests(tabIdentifier: "windowtab1")
```

Expected: all tests PASS, including every CSV import test untouched by this feature.

- [ ] **Step 5: Commit**

```bash
git add PersonalFinanceTraker/PersonalFinanceTrakerUITests/
git commit -m "test: add end-to-end UI test for Excel import"
```

---

## Self-Review Notes

- **Spec coverage:** multi-sheet picker (Task 5-6) ✓, single generic error message (Task 3, `XLSXReadError.unreadable`) ✓, canonical (not display-format) cell conversion (Task 4) ✓, CSVFile-pipeline reuse with zero changes to `CSVColumnMapper`/mapping views (Tasks 3-4, 6) ✓, unit + UI test coverage (Tasks 2-4, 8) ✓.
- **Placeholder scan:** Task 8's exact UI test code is intentionally deferred to a discovery step rather than guessed, because the existing UI test harness pattern (how it supplies a file to `fileImporter`) is unknown from the spec alone and guessing it risks unusable code; every other task has complete, concrete code.
- **Type consistency:** `XLSXWorkbook`, `XLSXReadError.unreadable`, `.sheetNames`, `.csvFile(forSheet:)`, `TransactionListViewModel.xlsxWorkbook`/`.loadExcelFile(from:)`/`.selectSheet(_:)` are named identically everywhere they're introduced (Tasks 3-4) and consumed (Tasks 6-7).
