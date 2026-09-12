package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.export.XlsxExportService
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

class ImportPipelineTest {
    @Test
    fun `csv parser preserves quoted delimiter and mapper applies expense type`() {
        val file = CsvImportParser.parse("Period,Category,Note,Income/Expense,Amount\n21/05/2026,Food,\"Lunch, downtown\",Expense,11.37")
        val result = TransactionImportMapper.validate(file, CsvColumnMapping("Period", "Amount", "Category", "Note", "Income/Expense"))

        assertEquals(0, result.rejectedRows)
        assertEquals("Lunch, downtown", result.transactions.single().note)
        assertEquals(BigDecimal("-11.37"), result.transactions.single().amount)
    }

    @Test
    fun `mapper accepts European thousands notation and selected positive expense signs`() {
        val file = CsvImportParser.parse("Date;Amount\n2026-05-21;1.234,50")
        val result = TransactionImportMapper.validate(file, CsvColumnMapping("Date", "Amount", dateFormat = "yyyy-MM-dd", signConvention = SignConvention.EXPENSES_POSITIVE))

        assertEquals(BigDecimal("-1234.50"), result.transactions.single().amount)
    }

    @Test
    fun `mapper recognizes abbreviated Italian export type`() {
        val file = CsvImportParser.parse("Date,Type,Amount\n2026-05-21,Exp.,330")
        val result = TransactionImportMapper.validate(file, CsvColumnMapping("Date", "Amount", type = "Type", dateFormat = "yyyy-MM-dd"))

        assertEquals(BigDecimal("-330"), result.transactions.single().amount)
    }

    @Test
    fun `mapper rejects invalid dates and amounts while retaining valid rows`() {
        val file = CsvImportParser.parse("Date,Amount\nnot-a-date,10\n2026-05-21,not-money\n2026-05-22,12")
        val result = TransactionImportMapper.validate(file, CsvColumnMapping("Date", "Amount", dateFormat = "yyyy-MM-dd"))

        assertEquals(2, result.rejectedRows)
        assertEquals(BigDecimal("12"), result.transactions.single().amount)
    }

    @Test
    fun `xlsx export round trips into the common mapping pipeline`() {
        val bytes = XlsxExportService.generate(listOf(transaction("Lunch, downtown", BigDecimal("-11.37"))))
        val file = XlsxImportService.read(bytes)

        assertEquals(listOf("Date", "Amount", "Currency", "Category", "Note", "Type"), file.headers)
        assertEquals("Lunch, downtown", file.rows.single()[4])
        val result = TransactionImportMapper.validate(file, CsvColumnMapping("Date", "Amount", "Category", "Note", "Type", "yyyy-MM-dd HH:mm:ss"))
        assertEquals(0, result.rejectedRows)
        assertEquals(BigDecimal("-11.37"), result.transactions.single().amount)
    }

    private fun transaction(note: String, amount: BigDecimal) = FinanceTransaction(
        id = "id", timestamp = Instant.parse("2026-05-21T00:00:00Z"), amount = amount,
        categoryId = "food", categoryLabel = "Food", note = note, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
    )
}
