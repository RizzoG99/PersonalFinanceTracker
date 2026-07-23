//
//  XLSXExportService.swift
//  PersonalFinanceTraker
//

import Foundation
import ZIPFoundation

enum XLSXWriteError: LocalizedError {
    case archiveFailed

    var errorDescription: String? {
        "Couldn't create the Excel file."
    }
}

/// Minimal .xlsx writer for exporting transactions. Same columns as
/// CSVExportService so the two export formats stay in sync.
///
/// ponytail: hand-rolled OOXML (5 XML parts in a ZIP) instead of an Excel
/// library — CoreXLSX is read-only. Dates are exported as plain text and
/// amounts as bare numbers; add styles.xml numFmts and date serials if
/// anyone needs Excel-native date/currency cells.
enum XLSXExportService {

    static func generateXLSX(from transactions: [TransactionSnapshot]) throws -> Data {
        let parts: [(path: String, xml: String)] = [
            ("[Content_Types].xml", contentTypesXML),
            ("_rels/.rels", rootRelsXML),
            ("xl/workbook.xml", workbookXML),
            ("xl/_rels/workbook.xml.rels", workbookRelsXML),
            ("xl/styles.xml", stylesXML),
            ("xl/worksheets/sheet1.xml", sheetXML(from: transactions)),
        ]

        let archive = try Archive(data: Data(), accessMode: .create)
        for part in parts {
            let data = Data(part.xml.utf8)
            try archive.addEntry(
                with: part.path,
                type: .file,
                uncompressedSize: Int64(data.count)
            ) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        guard let data = archive.data else { throw XLSXWriteError.archiveFailed }
        return data
    }

    // MARK: - Sheet

    private static let headers = ["Date", "Amount", "Currency", "Category", "Note", "Type"]

    private static func sheetXML(from transactions: [TransactionSnapshot]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var rows: [String] = [row(number: 1, cells: headers.map { .text($0) })]
        for (idx, tx) in transactions.enumerated() {
            rows.append(row(number: idx + 2, cells: [
                .text(dateFormatter.string(from: tx.timestamp)),
                .number("\(tx.amount)"),
                .text(tx.currencyCode),
                .text(tx.category),
                .text(tx.note),
                .text(tx.amount >= 0 ? "Income" : "Expense"),
            ]))
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    private enum CellValue {
        case text(String)
        case number(String)
    }

    /// Emits explicit cell references (A1, B2, …) — readers, including our own
    /// XLSXWorkbook importer, rely on them for column placement.
    private static func row(number: Int, cells: [CellValue]) -> String {
        let columns = ["A", "B", "C", "D", "E", "F"]
        let xml = cells.enumerated().map { idx, cell in
            let ref = "\(columns[idx])\(number)"
            switch cell {
            case .text(let value):
                return #"<c r="\#(ref)" t="inlineStr"><is><t xml:space="preserve">\#(escapeXML(value))</t></is></c>"#
            case .number(let value):
                return #"<c r="\#(ref)"><v>\#(value)</v></c>"#
            }
        }.joined()
        return #"<row r="\#(number)">\#(xml)</row>"#
    }

    private static func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Boilerplate package parts

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Transactions" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="12"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>
    """
}
