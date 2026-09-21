package com.rizzog99.personalfinancetracker.domain.import

/** Quote-aware CSV reader shared by the future mapping and preview steps. */
object CsvImportParser {
    data class CsvFile(val headers: List<String>, val rows: List<List<String>>, val delimiter: Char)

    fun parse(content: String): CsvFile {
        require(content.none { it == '\u0000' }) { "The selected file is not text." }
        val records = records(content)
        require(records.isNotEmpty()) { "The selected file is empty." }
        val delimiter = detectDelimiter(records.first())
        val headers = deduplicate(row(records.first(), delimiter).map(String::trim))
        require(headers.isNotEmpty() && headers.size <= 256) { "The selected file has no valid header." }
        return CsvFile(headers, records.drop(1).filter { it.isNotBlank() }.map { row(it, delimiter) }, delimiter)
    }

    private fun detectDelimiter(record: String): Char = listOf(',', ';', '\t').maxBy { candidate ->
        row(record, candidate).size
    }

    private fun deduplicate(headers: List<String>): List<String> {
        val seen = mutableMapOf<String, Int>()
        return headers.map { name ->
            val count = (seen[name] ?: 0) + 1
            seen[name] = count
            if (count == 1) name else "${name}_$count"
        }
    }

    private fun records(content: String): List<String> {
        val output = mutableListOf<String>()
        val current = StringBuilder()
        var quoted = false
        var index = 0
        val normalized = content.replace("\r\n", "\n")
        while (index < normalized.length) {
            val character = normalized[index]
            if (character == '"') {
                if (quoted && normalized.getOrNull(index + 1) == '"') {
                    current.append("\"\"")
                    index += 2
                    continue
                }
                quoted = !quoted
            }
            if (character == '\n' && !quoted) {
                output += current.toString()
                current.clear()
            } else current.append(character)
            index++
        }
        if (current.isNotEmpty()) output += current.toString()
        return output
    }

    private fun row(record: String, delimiter: Char): List<String> {
        val values = mutableListOf<String>()
        val current = StringBuilder()
        var quoted = false
        var index = 0
        while (index < record.length) {
            val character = record[index]
            when {
                character == '"' && quoted && record.getOrNull(index + 1) == '"' -> {
                    current.append('"'); index++
                }
                character == '"' -> quoted = !quoted
                character == delimiter && !quoted -> { values += current.toString(); current.clear() }
                else -> current.append(character)
            }
            index++
        }
        values += current.toString()
        return values
    }
}
