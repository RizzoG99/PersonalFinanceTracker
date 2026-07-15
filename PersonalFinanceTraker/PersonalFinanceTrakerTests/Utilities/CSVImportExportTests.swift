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

    @Test func handlesSimpleLineEndings() throws {
        let csv = "Date,Amount\n2024-01-15,100\n2024-01-16,50"
        let file = try CSVImportService.parse(csv)
        #expect(file.rowCount == 2)
    }

    @Test func quotedNewlinePreservedInField() throws {
        let csv = "Date,Description,Amount\n2024-01-15,\"Multi-line\ndescription\",100"
        let file = try CSVImportService.parse(csv)
        #expect(file.rowCount == 1)
        let row = file.preview(maxRows: 1)[0]
        #expect(row[1] == "Multi-line\ndescription")
    }

    @Test func quotedDelimiterInHeaderForDetection() throws {
        // Header has a delimiter inside quotes; detectDelimiter should ignore it
        let csv = "Date,Amount,Description\n2024-01-15,100,\"A, B, C\"\n2024-01-16,200,\"X, Y\""
        let file = try CSVImportService.parse(csv)
        // Should detect comma as delimiter (3 commas outside quotes in header)
        #expect(file.delimiter == ",")
        #expect(file.headers == ["Date", "Amount", "Description"])
        #expect(file.rowCount == 2)
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

    // MARK: - Stray / non-RFC quotes (files that don't quote fields at all)

    @Test func strayQuoteMidFieldDoesNotMergeRows() throws {
        let csv = "Date,Note,Amount\n2026-01-01,TV 30\" nuova,5\n2026-01-02,Cena,7"
        let file = try CSVImportService.parse(csv)
        #expect(file.rowCount == 2)
        #expect(file.preview(maxRows: 1)[0][1] == "TV 30\" nuova")
    }

    @Test func strayQuoteInHeaderDoesNotSwallowFile() throws {
        let csv = "Date,No\"te,Amount\n2026-01-01,a,5\n2026-01-02,b,7"
        let file = try CSVImportService.parse(csv)
        #expect(file.headers.count == 3)
        #expect(file.rowCount == 2)
    }

    @Test func unterminatedFieldStartQuoteFallsBackToLineSplit() throws {
        // Quote opens a field but never closes — parser must not merge the rest of the file
        let csv = "Date,Note,Amount\n2026-01-01,\"oops,5\n2026-01-02,b,7"
        let file = try CSVImportService.parse(csv)
        #expect(file.rowCount == 2)
    }

    @Test func crlfLineEndingsSplitCorrectly() throws {
        // \r\n is a single Character (grapheme cluster) in Swift — the splitter
        // must still detect it as a line ending (real-world export regression)
        let csv = "Date;Note;Amount\r\n21/05/2026;Spesa;5\r\n20/05/2026;Cena;7\r\n"
        let file = try CSVImportService.parse(csv)
        #expect(file.headers == ["Date", "Note", "Amount"])
        #expect(file.rowCount == 2)
        #expect(file.preview(maxRows: 1)[0] == ["21/05/2026", "Spesa", "5"])
    }

    @Test func absurdColumnCountThrows() {
        // A binary/one-line garbage file must not produce thousands of "headers"
        let garbage = Array(repeating: "x", count: 2000).joined(separator: ";")
        #expect(throws: CSVReadError.self) {
            _ = try CSVImportService.parse(garbage)
        }
    }

    @Test func parseRowStrayQuoteMidFieldIsLiteral() {
        let fields = CSVImportService.parseRow("2026-01-01,TV 30\" nuova,5", delimiter: ",")
        #expect(fields == ["2026-01-01", "TV 30\" nuova", "5"])
    }
}

// MARK: - CSVExportService

struct CSVExportServiceTests {

    private func makeTx(amount: Decimal, category: String, note: String = "") -> TransactionSnapshot {
        .test(timestamp: Date(timeIntervalSince1970: 0), amount: amount, note: note, category: category)
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
