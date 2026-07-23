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
    private let customDateFormatIds: Set<Int>

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

        let customDateFormatIds = Set(
            (styles.numberFormats?.items ?? [])
                .filter { isDateFormatCode($0.formatCode) }
                .map(\.id)
        )

        return XLSXWorkbook(
            file: coreFile,
            styles: styles,
            sharedStrings: sharedStrings,
            sheets: sheets,
            customDateFormatIds: customDateFormatIds
        )
    }

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
            .map { Self.columnIndex(from: $0.reference.column) }
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
            let idx = Self.columnIndex(from: cell.reference.column) - 1
            guard idx >= 0, idx < columnCount else { continue }
            result[idx] = stringify(cell)
        }
        return result
    }

    // CoreXLSX 0.14.2 doesn't expose ColumnReference.intValue; this workaround
    // calls String(describing:) to extract column letters. Relies on the default
    // description producing plain letters only (verified empirically by
    // XLSXWorkbookTests multi-column fixtures). Revisit on CoreXLSX upgrade.
    private static func columnIndex(from column: ColumnReference) -> Int {
        // Convert Excel column letters (A, B, ..., Z, AA, AB, ...) to 1-based index
        var result = 0
        let letters = String(describing: column).uppercased()
        for char in letters {
            if char.isLetter {
                result = result * 26 + (Int(char.asciiValue ?? 0) - Int(("A" as UnicodeScalar).value) + 1)
            }
        }
        return result
    }

    private func stringify(_ cell: Cell) -> String {
        let numFmtId = cell.format(in: styles)?.numberFormatId ?? 0
        if isDateNumberFormat(numFmtId), let raw = cell.value, let serial = Double(raw) {
            return Self.canonicalDateString(fromSerial: serial)
        }
        if cell.type == .sharedString {
            return sharedStrings.flatMap { cell.stringValue($0) } ?? ""
        }
        return cell.value ?? ""
    }

    private func isDateNumberFormat(_ id: Int) -> Bool {
        Self.isBuiltInDateNumberFormat(id) || customDateFormatIds.contains(id)
    }

    // Excel's built-in date/time numFmtIds (14-22 dates/times, 45-47 mm:ss
    // variants). IDs >= 164 are workbook-defined custom formats (e.g. a bank
    // export using "dd/MM/yyyy") — detected separately via isDateFormatCode
    // against each workbook's own <numFmts> since their meaning isn't fixed.
    static func isBuiltInDateNumberFormat(_ id: Int) -> Bool {
        (14...22).contains(id) || (45...47).contains(id)
    }

    // Heuristic: strip quoted literal text (e.g. "\"units\"") and bracketed
    // locale/color tags (e.g. "[$-409]"), then check for date/time pattern
    // letters. Good enough for real-world exports; doesn't attempt full
    // OOXML format-code parsing.
    static func isDateFormatCode(_ formatCode: String) -> Bool {
        var stripped = ""
        var inQuotes = false
        var inBrackets = false
        for char in formatCode {
            if char == "\"" { inQuotes.toggle(); continue }
            if char == "[" { inBrackets = true; continue }
            if char == "]" { inBrackets = false; continue }
            if inQuotes || inBrackets { continue }
            stripped.append(char)
        }
        return stripped.lowercased().contains(where: { "ymdhs".contains($0) })
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
}
