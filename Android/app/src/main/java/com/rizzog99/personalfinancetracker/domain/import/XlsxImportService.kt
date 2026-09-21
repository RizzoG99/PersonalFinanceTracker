package com.rizzog99.personalfinancetracker.domain.import

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/** Reads ordinary, unprotected XLSX workbooks into the common CSV mapping pipeline. */
object XlsxImportService {
    data class Workbook(val sheets: List<Sheet>) { init { require(sheets.isNotEmpty()) { "The workbook has no worksheets." } } }
    data class Sheet(val name: String, val file: CsvImportParser.CsvFile)

    fun read(bytes: ByteArray): CsvImportParser.CsvFile = readWorkbook(bytes).sheets.first().file

    fun readWorkbook(bytes: ByteArray): Workbook {
        val entries = mutableMapOf<String, String>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            generateSequence { zip.nextEntry }.forEach { entry -> entries[entry.name] = zip.readBytes().toString(Charsets.UTF_8) }
        }
        val shared = Regex("<si\\b[^>]*>(.*?)</si>", RegexOption.DOT_MATCHES_ALL).findAll(entries["xl/sharedStrings.xml"].orEmpty()).map { item ->
            Regex("<t[^>]*>(.*?)</t>", RegexOption.DOT_MATCHES_ALL).findAll(item.groupValues[1]).joinToString("") { decode(it.groupValues[1]) }
        }.toList()
        val names = Regex("<sheet\\b[^>]*name=\\\"([^\\\"]+)\\\"").findAll(entries["xl/workbook.xml"].orEmpty()).map { decode(it.groupValues[1]) }.toList()
        val fallback = entries.filterKeys { it.startsWith("xl/worksheets/") && it.endsWith(".xml") }.toSortedMap().entries
            .mapIndexed { index, (_, xml) -> Sheet(names.getOrElse(index) { "Sheet ${index + 1}" }, parseSheet(xml, shared)) }
        return Workbook(fallback)
    }

    private fun parseSheet(xml: String, shared: List<String>): CsvImportParser.CsvFile {
        val rows = Regex("<row\\b[^>]*>(.*?)</row>", RegexOption.DOT_MATCHES_ALL).findAll(xml).map { row ->
            val cells = mutableListOf<String>()
            Regex("<c\\b([^>]*)>(.*?)</c>", RegexOption.DOT_MATCHES_ALL).findAll(row.groupValues[1]).forEach { cell ->
                val attributes = cell.groupValues[1]
                val column = Regex("r=\\\"([A-Z]+)\\d+\\\"").find(attributes)?.groupValues?.get(1)?.columnIndex() ?: cells.size
                while (cells.size < column) cells += ""
                val body = cell.groupValues[2]
                val inline = Regex("<t[^>]*>(.*?)</t>", RegexOption.DOT_MATCHES_ALL).findAll(body).joinToString("") { decode(it.groupValues[1]) }
                val raw = Regex("<v[^>]*>(.*?)</v>", RegexOption.DOT_MATCHES_ALL).find(body)?.groupValues?.get(1).orEmpty()
                cells += if (inline.isNotEmpty()) inline else if (attributes.contains("t=\"s\"")) shared.getOrNull(raw.toIntOrNull() ?: -1).orEmpty() else decode(raw)
            }
            cells
        }.toList()
        require(rows.isNotEmpty()) { "The worksheet is empty." }
        return CsvImportParser.CsvFile(rows.first(), rows.drop(1), ',')
    }

    private fun String.columnIndex(): Int = fold(0) { result, letter -> result * 26 + letter.code - 'A'.code + 1 } - 1
    private fun decode(value: String) = value.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
}
