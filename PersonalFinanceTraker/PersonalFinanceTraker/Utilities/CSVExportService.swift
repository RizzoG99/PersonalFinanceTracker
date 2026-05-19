//
//  CSVExportService.swift
//  PersonalFinanceTraker
//
//  Created by Gemini CLI on 26/02/26.
//

import Foundation

/// Service for exporting transaction data to CSV format
public class CSVExportService {
    
    /// Generates a CSV string from an array of transaction models
    /// - Parameter transactions: The transactions to export
    /// - Returns: A formatted CSV string
    public static func generateCSV(from transactions: [TransactionModel]) -> String {
        let header = "Date,Amount,Currency,Category,Note,Type\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let rows = transactions.map { transaction in
            let date = dateFormatter.string(from: transaction.timestamp)
            let amount = "\(transaction.amount)"
            let currency = transaction.currencyCode
            let category = escapeCSV(transaction.category)
            let note = escapeCSV(transaction.note)
            let type = transaction.amount >= 0 ? "Income" : "Expense"
            
            return "\(date),\(amount),\(currency),\(category),\(note),\(type)"
        }.joined(separator: "\n")
        
        return header + rows
    }
    
    /// Escapes a string for CSV format by wrapping in quotes if it contains commas or quotes
    private static func escapeCSV(_ text: String) -> String {
        if text.contains(",") || text.contains(#"""#) {
            let escapedText = text.replacingOccurrences(of: #"""#, with: #""""#)
            return "\"\(escapedText)\""
        }
        return text
    }
}
