//
//  CSVColumnMapper.swift
//  PersonalFinanceTraker
//

import Foundation

struct ColumnMapping {
    var dateColumn: String? = nil
    var amountColumn: String? = nil
    var typeColumn: String? = nil
    var categoryColumn: String? = nil
    var noteColumn: String? = nil
    var currencyColumn: String? = nil
    var dateFormat: String = "yyyy-MM-dd HH:mm:ss"
    var defaultCurrency: String = "EUR"
}

struct MappedRow {
    let transaction: TransactionModel?
    let error: String?
    let rowIndex: Int

    var isValid: Bool { transaction != nil }
}

/// Sendable intermediate produced on a background thread — holds plain value types only.
/// TransactionModel (SwiftData @Model) is created later on the MainActor.
struct RawMappedRow: Sendable {
    struct TransactionData: Sendable {
        let timestamp: Date
        let amount: Decimal
        let note: String
        let category: String
        let resolvedCategoryUUID: UUID?
        let currencyCode: String
    }
    let data: TransactionData?
    let error: String?
    let rowIndex: Int
}

enum ImportStep: Hashable {
    case categoryMapping
    case results
}

class CSVColumnMapper {

    /// Background-safe mapping: takes UUID-keyed resolution to avoid passing non-Sendable CategoryModel.
    /// Call this from Task.detached; assemble MappedRow on MainActor afterwards.
    static func applyRaw(
        mapping: ColumnMapping,
        to file: CSVFile,
        categoryResolution: [String: UUID]
    ) -> [RawMappedRow] {
        guard let dateCol = mapping.dateColumn, let amountCol = mapping.amountColumn else {
            return []
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = mapping.dateFormat
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var results: [RawMappedRow] = []
        var rowIdx = 0

        file.processRows { row in
            let rowNum = rowIdx + 2

            func value(for column: String) -> String? {
                guard let idx = file.columnIndex(for: column), idx < row.count else { return nil }
                let v = row[idx].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }

            defer { rowIdx += 1 }

            // Skip transfer rows — they represent account moves, not income/expense
            if let typeCol = mapping.typeColumn, let typeStr = value(for: typeCol),
               Self.isTransfer(typeStr) {
                return
            }

            guard let dateStr = value(for: dateCol),
                  let date = dateFormatter.date(from: dateStr) else {
                results.append(RawMappedRow(
                    data: nil,
                    error: "Row \(rowNum): invalid date '\(value(for: dateCol) ?? "")' — expected \(mapping.dateFormat)",
                    rowIndex: rowIdx
                ))
                return
            }

            guard let amountStr = value(for: amountCol) else {
                results.append(RawMappedRow(
                    data: nil,
                    error: "Row \(rowNum): invalid amount ''",
                    rowIndex: rowIdx
                ))
                return
            }
            let cleanedAmount = amountStr.replacingOccurrences(of: ",", with: ".")
            // Use NSDecimalNumber to avoid Double's binary floating-point rounding
            let decimalNumber = NSDecimalNumber(string: cleanedAmount, locale: Locale(identifier: "en_US_POSIX"))
            guard decimalNumber != NSDecimalNumber.notANumber else {
                results.append(RawMappedRow(
                    data: nil,
                    error: "Row \(rowNum): invalid amount '\(amountStr)'",
                    rowIndex: rowIdx
                ))
                return
            }
            let rawAmount = decimalNumber.decimalValue

            let signedAmount: Decimal
            if let typeCol = mapping.typeColumn, let typeStr = value(for: typeCol) {
                let lower = typeStr.lowercased()
                let isIncome = lower.contains("inc") || lower.contains("income") ||
                               lower.contains("entrata") || lower.contains("credit")
                signedAmount = isIncome ? abs(rawAmount) : -abs(rawAmount)
            } else {
                signedAmount = rawAmount
            }

            let categoryStr = mapping.categoryColumn.flatMap { value(for: $0) } ?? ""
            let resolvedUUID = categoryResolution[categoryStr]
            let note = mapping.noteColumn.flatMap { value(for: $0) } ?? ""
            let currency = mapping.currencyColumn.flatMap { value(for: $0) } ?? mapping.defaultCurrency

            results.append(RawMappedRow(
                data: RawMappedRow.TransactionData(
                    timestamp: date,
                    amount: signedAmount,
                    note: note,
                    category: categoryStr.isEmpty ? "Other" : categoryStr,
                    resolvedCategoryUUID: resolvedUUID,
                    currencyCode: currency
                ),
                error: nil,
                rowIndex: rowIdx
            ))
        }

        return results
    }

    static func autoDetect(from file: CSVFile) -> ColumnMapping {
        var mapping = ColumnMapping()

        let dateKw      = ["date", "data", "datum", "fecha", "transaction date", "period", "periodo"]
        let amountKw    = ["amount", "importo", "betrag", "importe", "montant", "value", "sum"]
        let typeKw      = ["income/expense", "type", "tipo", "typ", "transaction type"]
        let categoryKw  = ["category", "categoria", "kategorie", "catégorie", "cat"]
        let noteKw      = ["note", "memo", "description", "desc", "detail", "remarks", "narration"]
        let currencyKw  = ["currency", "valuta", "moneda", "devise"]

        for header in file.headers {
            let lower = header.lowercased().trimmingCharacters(in: .whitespaces)
            if mapping.dateColumn == nil, dateKw.contains(where: { lower.contains($0) }) {
                mapping.dateColumn = header
            }
            if mapping.amountColumn == nil, amountKw.contains(where: { lower.contains($0) }) {
                mapping.amountColumn = header
            }
            if mapping.typeColumn == nil, typeKw.contains(where: { lower.contains($0) }) {
                mapping.typeColumn = header
            }
            if mapping.categoryColumn == nil, categoryKw.contains(where: { lower.contains($0) }) {
                mapping.categoryColumn = header
            }
            if mapping.noteColumn == nil, noteKw.contains(where: { lower.contains($0) }) {
                mapping.noteColumn = header
            }
            if mapping.currencyColumn == nil, currencyKw.contains(where: { lower.contains($0) }) {
                mapping.currencyColumn = header
            }
        }

        // Infer date format from the first data row
        if let dateCol = mapping.dateColumn,
           let idx = file.columnIndex(for: dateCol),
           let firstRow = file.preview(maxRows: 1).first,
           idx < firstRow.count {
            mapping.dateFormat = inferDateFormat(from: firstRow[idx].trimmingCharacters(in: CharacterSet.whitespaces))
        }

        return mapping
    }

    static func isTransfer(_ typeString: String) -> Bool {
        let lower = typeString.lowercased()
        return lower.contains("transfer") || lower.contains("trasferim") ||
               lower == "giro" || lower.contains("giroconto")
    }

    /// Unique category values from the CSV, excluding rows whose type column marks them as transfers.
    static func uniqueCategories(from file: CSVFile, mapping: ColumnMapping) -> [String] {
        guard let catCol = mapping.categoryColumn,
              let catIdx = file.columnIndex(for: catCol) else { return [] }
        let typeIdx = mapping.typeColumn.flatMap { file.columnIndex(for: $0) }
        var seen = Set<String>()
        var result: [String] = []
        file.processRows { row in
            // Skip transfers
            if let tIdx = typeIdx, tIdx < row.count,
               isTransfer(row[tIdx].trimmingCharacters(in: .whitespaces)) { return }
            guard catIdx < row.count else { return }
            let val = row[catIdx].trimmingCharacters(in: .whitespaces)
            if !val.isEmpty && seen.insert(val).inserted {
                result.append(val)
            }
        }
        return result
    }

    private static func inferDateFormat(from sample: String) -> String {
        let candidates: [(String, String)] = [
            // Unambiguous ISO formats first
            ("^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$", "yyyy-MM-dd HH:mm:ss"),
            ("^\\d{4}-\\d{2}-\\d{2}$",                       "yyyy-MM-dd"),
            // Short year slash
            ("^\\d{2}/\\d{2}/\\d{2}$",                       "MM/dd/yy"),
            // Dash-separated day-first (unambiguous: day > 12 distinguishes, but we can't know)
            ("^\\d{2}-\\d{2}-\\d{4}$",                       "dd-MM-yyyy"),
            // Slash-separated: can't distinguish dd/MM from MM/dd; default European (dd/MM)
            // User can override via the date format picker in the column mapping screen
            ("^\\d{2}/\\d{2}/\\d{4}$",                       "dd/MM/yyyy"),
        ]
        for (pattern, fmt) in candidates {
            if sample.range(of: pattern, options: .regularExpression) != nil {
                return fmt
            }
        }
        return "yyyy-MM-dd HH:mm:ss"
    }
}
