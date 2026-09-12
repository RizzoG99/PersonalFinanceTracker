package com.rizzog99.personalfinancetracker.domain.export

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Minimal standards-compliant XLSX writer using inline strings; keeps Android exports readable by Excel and Numbers. */
object XlsxExportService {
    private val dateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.ROOT).withZone(ZoneId.systemDefault())
    fun generate(transactions: List<FinanceTransaction>): ByteArray {
        val rows = listOf(listOf("Date", "Amount", "Currency", "Category", "Note", "Type")) + transactions.map {
            listOf(dateFormatter.format(it.timestamp), it.amount.toPlainString(), it.currencyCode, it.categoryLabel, it.note, if (it.amount.signum() >= 0) "Income" else "Expense")
        }
        return ByteArrayOutputStream().use { bytes -> ZipOutputStream(bytes).use { zip ->
            fun entry(name: String, value: String) { zip.putNextEntry(ZipEntry(name)); zip.write(value.toByteArray()); zip.closeEntry() }
            entry("[Content_Types].xml", """<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>""")
            entry("_rels/.rels", """<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>""")
            entry("xl/workbook.xml", """<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Transactions" sheetId="1" r:id="rId1"/></sheets></workbook>""")
            entry("xl/_rels/workbook.xml.rels", """<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>""")
            val sheet = rows.mapIndexed { rowIndex, row -> "<row r=\"${rowIndex + 1}\">" + row.mapIndexed { column, value -> "<c r=\"${('A'.code + column).toChar()}${rowIndex + 1}\" t=\"inlineStr\"><is><t>${escape(value)}</t></is></c>" }.joinToString("") + "</row>" }.joinToString("")
            entry("xl/worksheets/sheet1.xml", """<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>$sheet</sheetData></worksheet>""")
        }; bytes.toByteArray() }
    }
    private fun escape(value: String) = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}
