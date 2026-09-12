package com.rizzog99.personalfinancetracker.domain.import

import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/** Reads the first worksheet of ordinary unprotected XLSX files into the common CSV mapping pipeline. */
object XlsxImportService {
    fun read(bytes: ByteArray): CsvImportParser.CsvFile {
        val entries = mutableMapOf<String, String>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            generateSequence { zip.nextEntry }.forEach { entry -> entries[entry.name] = zip.readBytes().toString(Charsets.UTF_8) }
        }
        val shared = Regex("<si>.*?<t[^>]*>(.*?)</t>.*?</si>", RegexOption.DOT_MATCHES_ALL).findAll(entries["xl/sharedStrings.xml"].orEmpty()).map { decode(it.groupValues[1]) }.toList()
        val sheet = entries["xl/worksheets/sheet1.xml"] ?: error("No worksheet found")
        val rows = Regex("<row[^>]*>(.*?)</row>", RegexOption.DOT_MATCHES_ALL).findAll(sheet).map { row ->
            Regex("<c([^>]*)>(.*?)</c>", RegexOption.DOT_MATCHES_ALL).findAll(row.groupValues[1]).map { cell ->
                val attributes = cell.groupValues[1]; val body = cell.groupValues[2]
                val inline = Regex("<t[^>]*>(.*?)</t>", RegexOption.DOT_MATCHES_ALL).find(body)?.groupValues?.get(1)
                val value = Regex("<v>(.*?)</v>").find(body)?.groupValues?.get(1).orEmpty()
                decode(inline ?: if (attributes.contains("t=\"s\"")) shared.getOrNull(value.toIntOrNull() ?: -1).orEmpty() else value)
            }.toList()
        }.toList()
        require(rows.isNotEmpty()) { "The worksheet is empty." }
        return CsvImportParser.CsvFile(rows.first(), rows.drop(1), ',')
    }
    private fun decode(value: String) = value.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
}
