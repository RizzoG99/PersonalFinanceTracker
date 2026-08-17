//
//  TransactionType.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI


public enum TransactionType: String, CaseIterable, Sendable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"

    var systemImage: String {
        switch self {
        case .income:
            return "arrow.down.circle.fill"
        case .expense:
            return "arrow.up.circle.fill"
        case .transfer:
            return "arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .income:
            return .positive
        case .expense:
            return .negative
        case .transfer:
            return .accentIndigo
        }
    }
}
