import Testing
import Foundation
@testable import PersonalFinanceTraker

/// Round-trip tests: the generated .xlsx is verified by reading it back with
/// the app's own importer (XLSXWorkbook / CoreXLSX) — an invalid file
/// wouldn't parse at all.
struct XLSXExportServiceTests {

    private func roundTrip(_ transactions: [TransactionSnapshot]) throws -> CSVFile {
        let data = try XLSXExportService.generateXLSX(from: transactions)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLSXExportServiceTests-\(UUID().uuidString).xlsx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let workbook = try XLSXWorkbook.read(from: url)
        #expect(workbook.sheetNames == ["Transactions"])
        return try workbook.csvFile(forSheet: "Transactions")
    }

    @Test func emptyExportHasHeaderRowOnly() throws {
        let file = try roundTrip([])
        #expect(file.headers == ["Date", "Amount", "Currency", "Category", "Note", "Type"])
        #expect(file.rowCount == 0)
    }

    @Test func exportedRowsSurviveRoundTrip() throws {
        let timestamp = ISO8601DateFormatter().date(from: "2026-07-23T14:30:00Z")!
        let file = try roundTrip([
            .test(timestamp: timestamp, amount: -12.5, note: "Coffee ☕️, \"double\" & <hot>", category: "Food"),
            .test(timestamp: timestamp, amount: 1000, note: "", category: "Salary"),
        ])
        #expect(file.rowCount == 2)
        let rows = file.preview(maxRows: 2)

        #expect(rows[0][1] == "-12.5")
        #expect(rows[0][2] == "EUR")
        #expect(rows[0][3] == "Food")
        #expect(rows[0][4] == "Coffee ☕️, \"double\" & <hot>")
        #expect(rows[0][5] == "Expense")

        #expect(rows[1][1] == "1000")
        #expect(rows[1][4] == "")
        #expect(rows[1][5] == "Income")

        // Date is exported as local-time text, same format as the CSV export
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        #expect(rows[0][0] == formatter.string(from: timestamp))
    }
}
