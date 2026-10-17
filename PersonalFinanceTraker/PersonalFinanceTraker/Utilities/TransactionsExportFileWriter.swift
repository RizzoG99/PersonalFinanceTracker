import Foundation

enum TransactionsExportFormat: String, Sendable {
    case csv, xlsx
}

/// Builds export data away from the main actor, then writes a shareable file
/// whose extension lets the system infer the correct document type and icon.
actor TransactionsExportFileWriter {
    func write(
        transactions: [TransactionSnapshot],
        format: TransactionsExportFormat,
        date: Date = .now,
        directory: URL = .temporaryDirectory
    ) throws -> URL {
        let data: Data
        switch format {
        case .csv:
            data = Data(CSVExportService.generateCSV(from: transactions).utf8)
        case .xlsx:
            data = try XLSXExportService.generateXLSX(from: transactions)
        }

        let stamp = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = directory.appending(path: "Transactions-\(stamp).\(format.rawValue)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
