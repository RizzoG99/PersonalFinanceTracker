//
//  CSVImportService.swift
//  PersonalFinanceTraker
//

import Foundation

struct CSVFile {
    let headers: [String]
    let delimiter: Character
    // Raw unparsed data lines (no header). Each line is (1-based line number in original file, text).
    // Columns are parsed lazily on demand.
    private let lines: [(lineNumber: Int, text: String)]

    init(headers: [String], delimiter: Character, lines: [(lineNumber: Int, text: String)]) {
        self.headers = headers
        self.delimiter = delimiter
        self.lines = lines
    }

    var rowCount: Int { lines.count }

    func columnIndex(for name: String) -> Int? {
        headers.firstIndex(of: name)
    }

    /// Returns unique non-empty values in a column, parsing each line on demand.
    func uniqueValues(forColumn name: String) -> [String] {
        guard let idx = columnIndex(for: name) else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for (_, text) in lines {
            let fields = CSVImportService.parseRow(text, delimiter: delimiter)
            guard idx < fields.count else { continue }
            let val = fields[idx].trimmingCharacters(in: .whitespaces)
            if !val.isEmpty && seen.insert(val).inserted {
                result.append(val)
            }
        }
        return result
    }

    /// Yields parsed rows one at a time — never holds all columns in memory at once.
    func processRows(_ handler: ([String]) -> Void) {
        for (_, text) in lines {
            handler(CSVImportService.parseRow(text, delimiter: delimiter))
        }
    }

    /// Yields parsed rows with their original line numbers.
    func processRowsWithLineNumbers(_ handler: (Int, [String]) -> Void) {
        for (lineNumber, text) in lines {
            handler(lineNumber, CSVImportService.parseRow(text, delimiter: delimiter))
        }
    }

    /// First N lines parsed into columns, for the preview table only.
    func preview(maxRows: Int = 3) -> [[String]] {
        lines.prefix(maxRows).map { CSVImportService.parseRow($0.text, delimiter: delimiter) }
    }
}

enum CSVReadError: LocalizedError {
    case unreadableFile
    case emptyFile
    case missingHeader
    case binaryFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Could not read the file. Make sure it is a valid CSV."
        case .emptyFile: return "The file is empty."
        case .missingHeader: return "The file must have a header row."
        case .binaryFile: return "This looks like a binary file (e.g. Excel .xlsx). Export your data as CSV and try again."
        }
    }
}

class CSVImportService {

    static func read(from url: URL) throws -> CSVFile {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw CSVReadError.unreadableFile
        }

        // ZIP magic (xlsx/numbers/docx all start with "PK") or embedded NULs:
        // not a text file — latin1 would "decode" it into garbage otherwise
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.prefix(4096).contains(0) {
            throw CSVReadError.binaryFile
        }

        let content: String
        if let utf8 = String(data: data, encoding: .utf8) {
            content = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            content = latin1
        } else {
            throw CSVReadError.unreadableFile
        }

        return try parse(content)
    }

    static func parse(_ content: String) throws -> CSVFile {
        // Split on newlines in a quote-aware manner to handle quoted newlines
        let rawLines = splitLinesQuoteAware(content)

        guard !rawLines.isEmpty else { throw CSVReadError.emptyFile }

        let delimiter = detectDelimiter(rawLines[0])

        // Deduplicate column names (e.g. "Accounts" → "Accounts", "Accounts_2")
        let rawHeaders = parseRow(rawLines[0], delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rawHeaders.isEmpty else { throw CSVReadError.missingHeader }
        // ponytail: no real CSV has hundreds of columns — a huge count means a
        // malformed/binary file, and downstream UI (pickers) must never see it
        guard rawHeaders.count <= 256 else { throw CSVReadError.unreadableFile }

        var seen: [String: Int] = [:]
        let headers = rawHeaders.map { name -> String in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name)_\(count)"
        }

        // Store raw lines with their 1-based line numbers from the original file
        // dropFirst() removes header, enumerated() gives us index (0-based for data rows)
        let dataLines = Array(rawLines.dropFirst()).enumerated().map { idx, text in
            (lineNumber: idx + 2, text: text)  // idx 0 → line 2 (line 1 is header)
        }

        return CSVFile(headers: headers, delimiter: delimiter, lines: dataLines)
    }

    private static func detectDelimiter(_ line: String) -> Character {
        // Count delimiters only outside quoted sections (field-start quotes only;
        // stray quotes mid-field are literal, same rules as parseRow)
        var inQuotes = false
        var atFieldStart = true
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    // Check for escaped quote ("")
                    if next < line.endIndex && line[next] == "\"" {
                        i = line.index(after: next)
                        continue
                    }
                    if next == line.endIndex || delimiterCandidates.contains(line[next]) {
                        inQuotes = false
                    }
                }
            } else if ch == "\"" && atFieldStart {
                inQuotes = true
                atFieldStart = false
            } else if counts[ch] != nil {
                counts[ch, default: 0] += 1
                atFieldStart = true
            } else {
                atFieldStart = false
            }
            i = line.index(after: i)
        }

        let candidates: [(Character, Int)] = [
            (",", counts[","]!),
            (";", counts[";"]!),
            ("\t", counts["\t"]!),
        ]
        return candidates.max(by: { $0.1 < $1.1 })?.0 ?? ","
    }

    // Quote handling follows RFC 4180 semantics: a quote only opens a quoted
    // region at the start of a field, and only closes one right before a
    // delimiter or line ending. A stray `"` inside an unquoted field (common
    // in exports that don't quote at all, e.g. `TV 30" nuova`) is literal —
    // it must never swallow the rest of the file.
    private static let delimiterCandidates: Set<Character> = [",", ";", "\t"]

    private static func splitLinesQuoteAware(_ content: String) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var inQuotes = false
        var atFieldStart = true  // start of line or right after a delimiter
        var i = 0
        // In Swift, "\r\n" is a SINGLE Character (grapheme cluster), so it matches
        // neither "\r" nor "\n" below. Normalize CRLF first or CRLF files never split.
        let chars = Array(content.replacingOccurrences(of: "\r\n", with: "\n"))

        while i < chars.count {
            let ch = chars[i]

            if inQuotes {
                if ch == "\"" {
                    // Escaped quote ("") — keep both chars for parseRow
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentLine.append("\"\"")
                        i += 2
                        continue
                    }
                    // Closing quote only when followed by delimiter/newline/EOF;
                    // otherwise it's a literal quote inside the quoted field.
                    let next = i + 1
                    if next >= chars.count || delimiterCandidates.contains(chars[next])
                        || chars[next] == "\n" || chars[next] == "\r" {
                        inQuotes = false
                    }
                }
                currentLine.append(ch)
                i += 1
            } else if ch == "\"" && atFieldStart {
                inQuotes = true
                atFieldStart = false
                currentLine.append(ch)
                i += 1
            } else if ch == "\n" || ch == "\r" {
                if ch == "\r" {
                    i += 1
                    // Skip \n if it follows \r
                    if i < chars.count && chars[i] == "\n" {
                        i += 1
                    }
                } else {  // ch == "\n"
                    i += 1
                }
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = ""
                }
                atFieldStart = true
            } else {
                atFieldStart = delimiterCandidates.contains(ch)
                currentLine.append(ch)
                i += 1
            }
        }

        if inQuotes {
            // ponytail: a field-start quote never closed — the file doesn't use
            // RFC quoting. Re-split naively on newlines instead of merging everything.
            return content
                .components(separatedBy: "\n")
                .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
                .filter { !$0.isEmpty }
        }

        // Don't forget the last line
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    static func parseRow(_ line: String, delimiter: Character = ",") -> [String] {
        // Fast path: no quotes → use split directly (avoids character-by-character overhead)
        if !line.contains("\"") {
            return line.split(separator: delimiter, omittingEmptySubsequences: false)
                .map(String.init)
        }
        // Slow path: quoted fields. Quotes only open at field start and only
        // close before a delimiter or end of line; stray quotes are literal.
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var atFieldStart = true
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        // Escaped quote ("")
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    }
                    if next == line.endIndex || line[next] == delimiter {
                        inQuotes = false
                    } else {
                        current.append(ch)
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" && atFieldStart {
                inQuotes = true
                atFieldStart = false
            } else if ch == delimiter {
                fields.append(current)
                current = ""
                atFieldStart = true
            } else {
                current.append(ch)
                atFieldStart = false
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
