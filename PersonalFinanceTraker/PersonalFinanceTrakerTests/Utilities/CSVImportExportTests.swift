import Testing
import Foundation
@testable import PersonalFinanceTraker

// MARK: - CSVImportService

struct CSVImportServiceTests {

    @Test func parsesCommaDelimitedCSV() throws {
        let csv = "Date,Amount,Category\n2024-01-15,100,Food\n2024-01-16,50,Transport"
        let file = try CSVImportService.parse(csv)
        #expect(file.headers == ["Date", "Amount", "Category"])
        #expect(file.rowCount == 2)
        #expect(file.delimiter == ",")
    }

    @Test func parsesSemicolonDelimitedCSV() throws {
        let csv = "Date;Amount;Category\n2024-01-15;100;Food"
        let file = try CSVImportService.parse(csv)
        #expect(file.delimiter == ";")
        #expect(file.rowCount == 1)
    }

    @Test func emptyContentThrowsEmptyFile() {
        #expect(throws: CSVReadError.emptyFile) {
            try CSVImportService.parse("")
        }
    }

    @Test func headerOnlyProducesZeroRows() throws {
        let file = try CSVImportService.parse("Date,Amount,Category")
        #expect(file.rowCount == 0)
    }

    @Test func windowsLineEndingsStripped() throws {
        let csv = "Date,Amount\r\n2024-01-15,100\r\n"
        let file = try CSVImportService.parse(csv)
        #expect(file.rowCount == 1)
    }

    @Test func duplicateHeadersDeduped() throws {
        let file = try CSVImportService.parse("Accounts,Amount,Accounts\n1,2,3")
        #expect(file.headers[0] == "Accounts")
        #expect(file.headers[2] == "Accounts_2")
    }

    @Test func columnIndexReturnsCorrectIndex() throws {
        let file = try CSVImportService.parse("Date,Amount,Category\n2024-01-15,100,Food")
        #expect(file.columnIndex(for: "Amount") == 1)
        #expect(file.columnIndex(for: "Nonexistent") == nil)
    }

    @Test func uniqueValuesInColumnDeduplicates() throws {
        let csv = "Category,Amount\nFood,10\nTransport,20\nFood,15"
        let file = try CSVImportService.parse(csv)
        let cats = file.uniqueValues(forColumn: "Category")
        #expect(Set(cats) == Set(["Food", "Transport"]))
    }

    @Test func parseRowHandlesQuotedFieldWithComma() {
        let row = #""Food, Drinks",25.00"#
        let fields = CSVImportService.parseRow(row, delimiter: ",")
        #expect(fields[0] == "Food, Drinks")
        #expect(fields[1] == "25.00")
    }

    @Test func parseRowHandlesDoubleQuoteEscape() {
        let row = #""He said ""hello""",10"#
        let fields = CSVImportService.parseRow(row, delimiter: ",")
        #expect(fields[0] == #"He said "hello""#)
    }

    @Test func parseRowWithNoQuotesUsesSimpleSplit() {
        let fields = CSVImportService.parseRow("2024-01-15,100,Food", delimiter: ",")
        #expect(fields == ["2024-01-15", "100", "Food"])
    }
}

// MARK: - CSVExportService

struct CSVExportServiceTests {

    private func makeTx(amount: Decimal, category: String, note: String = "") -> TransactionModel {
        TransactionModel(timestamp: Date(timeIntervalSince1970: 0), amount: amount, note: note, category: category)
    }

    @Test func generateCSVHasCorrectHeader() {
        let csv = CSVExportService.generateCSV(from: [])
        #expect(csv.hasPrefix("Date,Amount,Currency,Category,Note,Type\n"))
    }

    @Test func incomeTransactionLabeledIncome() {
        let csv = CSVExportService.generateCSV(from: [makeTx(amount: 100, category: "Salary")])
        #expect(csv.contains("Income"))
    }

    @Test func expenseTransactionLabeledExpense() {
        let csv = CSVExportService.generateCSV(from: [makeTx(amount: -50, category: "Food")])
        #expect(csv.contains("Expense"))
    }

    @Test func categoryWithCommaIsQuoted() {
        let csv = CSVExportService.generateCSV(from: [makeTx(amount: -10, category: "Food, Drinks")])
        #expect(csv.contains(#""Food, Drinks""#))
    }

    @Test func plainCategoryIsNotQuoted() {
        let csv = CSVExportService.generateCSV(from: [makeTx(amount: -10, category: "Food")])
        #expect(csv.contains(",Food,"))
    }

    @Test func emptyTransactionsProducesHeaderOnly() {
        let lines = CSVExportService.generateCSV(from: [])
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        #expect(lines.count == 1)
    }
}
