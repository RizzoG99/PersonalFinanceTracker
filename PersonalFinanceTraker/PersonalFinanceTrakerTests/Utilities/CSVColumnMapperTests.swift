import Testing
import Foundation
@testable import PersonalFinanceTraker

struct CSVColumnMapperTests {

    private func makeFile(_ content: String) throws -> CSVFile {
        try CSVImportService.parse(content)
    }

    // MARK: autoDetect

    @Test func autoDetectFindsEnglishDateAmountCategory() throws {
        let file = try makeFile("Date,Amount,Category\n2024-01-15,100,Food")
        let m = CSVColumnMapper.autoDetect(from: file)
        #expect(m.dateColumn == "Date")
        #expect(m.amountColumn == "Amount")
        #expect(m.categoryColumn == "Category")
    }

    @Test func autoDetectItalianHeaders() throws {
        let file = try makeFile("Data,Importo,Categoria\n2024-01-15,100,Cibo")
        let m = CSVColumnMapper.autoDetect(from: file)
        #expect(m.dateColumn == "Data")
        #expect(m.amountColumn == "Importo")
        #expect(m.categoryColumn == "Categoria")
    }

    @Test func autoDetectInfersISODateTimeFormat() throws {
        let file = try makeFile("Date,Amount\n2024-01-15 10:30:00,100")
        let m = CSVColumnMapper.autoDetect(from: file)
        #expect(m.dateFormat == "yyyy-MM-dd HH:mm:ss")
    }

    @Test func autoDetectInfersShortISODateFormat() throws {
        let file = try makeFile("Date,Amount\n2024-01-15,100")
        let m = CSVColumnMapper.autoDetect(from: file)
        #expect(m.dateFormat == "yyyy-MM-dd")
    }

    @Test func autoDetectNoteAndCurrencyColumns() throws {
        let file = try makeFile("Date,Amount,Note,Currency\n2024-01-15,100,Coffee,EUR")
        let m = CSVColumnMapper.autoDetect(from: file)
        #expect(m.noteColumn == "Note")
        #expect(m.currencyColumn == "Currency")
    }

    // MARK: isIncome

    @Test func isIncomeEnglish() {
        #expect(CSVColumnMapper.isIncome("Income"))
        #expect(CSVColumnMapper.isIncome("Incoming"))
        #expect(CSVColumnMapper.isIncome("INCOME"))
        #expect(CSVColumnMapper.isIncome("Credit"))
    }

    @Test func isIncomeItalian() {
        #expect(CSVColumnMapper.isIncome("Entrata"))
        #expect(CSVColumnMapper.isIncome("entrate"))
    }

    @Test func isIncomeFalseForExpense() {
        #expect(!CSVColumnMapper.isIncome("Expense"))
        #expect(!CSVColumnMapper.isIncome("Food"))
        #expect(!CSVColumnMapper.isIncome("Outgoing"))
    }

    // MARK: isTransfer

    @Test func isTransferEnglish() {
        #expect(CSVColumnMapper.isTransfer("Transfer"))
        #expect(CSVColumnMapper.isTransfer("Bank Transfer"))
        #expect(CSVColumnMapper.isTransfer("TRANSFER"))
    }

    @Test func isTransferItalian() {
        #expect(CSVColumnMapper.isTransfer("Trasferimento"))
        #expect(CSVColumnMapper.isTransfer("Giro"))
        #expect(CSVColumnMapper.isTransfer("Giroconto bancario"))
    }

    @Test func isTransferFalseForNonTransfer() {
        #expect(!CSVColumnMapper.isTransfer("Food"))
        #expect(!CSVColumnMapper.isTransfer("Income"))
        #expect(!CSVColumnMapper.isTransfer("Salary"))
    }

    // MARK: uniqueCategories

    @Test func uniqueCategoriesExcludesTransferRows() throws {
        let csv = "Category,Type\nFood,Expense\nSalary,Income\nSavings,Transfer"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.categoryColumn = "Category"
        m.typeColumn = "Type"
        let cats = CSVColumnMapper.uniqueCategories(from: file, mapping: m)
        #expect(!cats.contains("Savings"))
        #expect(cats.contains("Food"))
        #expect(cats.contains("Salary"))
    }

    @Test func uniqueCategoriesReturnsEmptyWithNoColumnMapping() throws {
        let file = try makeFile("Date,Amount\n2024-01-15,100")
        let cats = CSVColumnMapper.uniqueCategories(from: file, mapping: ColumnMapping())
        #expect(cats.isEmpty)
    }

    // MARK: applyRaw

    @Test func applyRawReturnsEmptyWhenMappingHasNoDateOrAmount() throws {
        let file = try makeFile("Note\nHello")
        let result = CSVColumnMapper.applyRaw(mapping: ColumnMapping(), to: file, categoryResolution: [:])
        #expect(result.isEmpty)
    }

    @Test func applyRawParsesValidRow() throws {
        let csv = "Date,Amount,Category\n2024-01-15,-50.00,Food"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.categoryColumn = "Category"
        m.dateFormat = "yyyy-MM-dd"
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 1)
        #expect(result[0].data != nil)
        #expect(result[0].data?.amount == Decimal(-50))
        #expect(result[0].data?.category == "Food")
    }

    @Test func applyRawSkipsTransferRows() throws {
        let csv = "Date,Amount,Type\n2024-01-15,-50,Transfer\n2024-01-16,-30,Expense"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.typeColumn = "Type"
        m.dateFormat = "yyyy-MM-dd"
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 1)
    }

    @Test func applyRawReportsCorrectLineNumbersWithQuotedNewlines() throws {
        // A quoted newline in row 1 doesn't change the actual line number of row 2
        let csv = "Date,Amount,Description\n2024-01-15,100,\"Multi\nline\"\n2024-01-17,200,Valid"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.dateFormat = "yyyy-MM-dd"
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 2)
        #expect(result[0].data?.amount == Decimal(100))
        #expect(result[1].data?.amount == Decimal(200))
    }

    @Test func applyRawErrorMessagesContainOriginalLineNumber() throws {
        let csv = "Date,Amount\n2024-01-15,100\ninvalid-date,200"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.dateFormat = "yyyy-MM-dd"
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        // First row valid, second row invalid
        #expect(result.count == 2)
        #expect(result[0].data != nil)
        #expect(result[1].error != nil)
        // Error should reference line 3 (header is line 1, first data row is line 2, second data row is line 3)
        #expect(result[1].error?.contains("Row 3") == true)
    }

    // MARK: Sign Convention

    @Test func signConventionSignedKeepsAmountAsIs() throws {
        let csv = "Date,Amount\n2024-01-15,100\n2024-01-16,-50"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.dateFormat = "yyyy-MM-dd"
        m.signConvention = .signed
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 2)
        #expect(result[0].data?.amount == Decimal(100))
        #expect(result[1].data?.amount == Decimal(-50))
    }

    @Test func signConventionAllExpensesConvertsToNegative() throws {
        let csv = "Date,Amount\n2024-01-15,100\n2024-01-16,50"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.dateFormat = "yyyy-MM-dd"
        m.signConvention = .allExpenses
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 2)
        #expect(result[0].data?.amount == Decimal(-100))
        #expect(result[1].data?.amount == Decimal(-50))
    }

    @Test func signConventionAllIncomeConvertsToPositive() throws {
        let csv = "Date,Amount\n2024-01-15,100\n2024-01-16,-50"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.dateFormat = "yyyy-MM-dd"
        m.signConvention = .allIncome
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 2)
        #expect(result[0].data?.amount == Decimal(100))
        #expect(result[1].data?.amount == Decimal(50))
    }

    @Test func typeColumnOverridesSignConvention() throws {
        let csv = "Date,Amount,Type\n2024-01-15,100,Income\n2024-01-16,50,Expense"
        let file = try makeFile(csv)
        var m = ColumnMapping()
        m.dateColumn = "Date"
        m.amountColumn = "Amount"
        m.typeColumn = "Type"
        m.dateFormat = "yyyy-MM-dd"
        m.signConvention = .allExpenses  // This should be ignored when typeColumn is present
        let result = CSVColumnMapper.applyRaw(mapping: m, to: file, categoryResolution: [:])
        #expect(result.count == 2)
        #expect(result[0].data?.amount == Decimal(100))  // Income, should be positive
        #expect(result[1].data?.amount == Decimal(-50))  // Expense, should be negative
    }
}
