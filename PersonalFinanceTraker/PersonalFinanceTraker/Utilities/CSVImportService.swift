//
//  CSVImportService.swift
//  PersonalFinanceTraker
//

import Foundation

struct CSVFile {
    let headers: [String]
    let delimiter: Character
    // Raw unparsed data lines (no header). Columns are parsed lazily on demand.
    private let lines: [String]

    init(headers: [String], delimiter: Character, lines: [String]) {
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
        for line in lines {
            let fields = CSVImportService.parseRow(line, delimiter: delimiter)
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
        for line in lines {
            handler(CSVImportService.parseRow(line, delimiter: delimiter))
        }
    }

    /// First N lines parsed into columns, for the preview table only.
    func preview(maxRows: Int = 3) -> [[String]] {
        lines.prefix(maxRows).map { CSVImportService.parseRow($0, delimiter: delimiter) }
    }
}

enum CSVReadError: LocalizedError {
    case unreadableFile
    case emptyFile
    case missingHeader

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Could not read the file. Make sure it is a valid CSV."
        case .emptyFile: return "The file is empty."
        case .missingHeader: return "The file must have a header row."
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
        // Split on newlines in one pass — far cheaper than character-by-character building
        var rawLines = content.components(separatedBy: "\n")

        // Strip \r from Windows line endings and drop empty lines
        rawLines = rawLines
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }

        guard !rawLines.isEmpty else { throw CSVReadError.emptyFile }

        let delimiter = detectDelimiter(rawLines[0])

        // Deduplicate column names (e.g. "Accounts" → "Accounts", "Accounts_2")
        let rawHeaders = parseRow(rawLines[0], delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rawHeaders.isEmpty else { throw CSVReadError.missingHeader }

        var seen: [String: Int] = [:]
        let headers = rawHeaders.map { name -> String in
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return count == 1 ? name : "\(name)_\(count)"
        }

        // Store only the raw line strings — columns are parsed on demand
        let lines = Array(rawLines.dropFirst())

        return CSVFile(headers: headers, delimiter: delimiter, lines: lines)
    }

    private static func detectDelimiter(_ line: String) -> Character {
        let candidates: [(Character, Int)] = [
            (",", line.filter { $0 == "," }.count),
            (";", line.filter { $0 == ";" }.count),
            ("\t", line.filter { $0 == "\t" }.count),
        ]
        return candidates.max(by: { $0.1 < $1.1 })?.0 ?? ","
    }

    static func parseRow(_ line: String, delimiter: Character = ",") -> [String] {
        // Fast path: no quotes → use split directly (avoids character-by-character overhead)
        if !line.contains("\"") {
            return line.split(separator: delimiter, omittingEmptySubsequences: false)
                .map(String.init)
        }
        // Slow path: quoted fields
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if ch == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
