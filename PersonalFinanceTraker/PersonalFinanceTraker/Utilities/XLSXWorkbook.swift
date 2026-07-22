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
