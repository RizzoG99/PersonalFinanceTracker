import Foundation
import Testing
@testable import PersonalFinanceTraker

struct TransactionsExportFileWriterTests {
    private func temporaryDirectory() throws -> URL {
        let directory = URL.temporaryDirectory
            .appending(path: "TransactionsExportFileWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func writesDatedCSVFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z"))

        let url = try await TransactionsExportFileWriter().write(
            transactions: [],
            format: .csv,
            date: date,
            directory: directory
        )

        #expect(url.lastPathComponent == "Transactions-2026-10-17.csv")
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.hasPrefix("Date,Amount,Currency,Category,Note,Type"))
    }

    @Test func writesDatedExcelFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z"))

        let url = try await TransactionsExportFileWriter().write(
            transactions: [],
            format: .xlsx,
            date: date,
            directory: directory
        )

        #expect(url.lastPathComponent == "Transactions-2026-10-17.xlsx")
        let workbook = try XLSXWorkbook.read(from: url)
        #expect(workbook.sheetNames == ["Transactions"])
    }
}
