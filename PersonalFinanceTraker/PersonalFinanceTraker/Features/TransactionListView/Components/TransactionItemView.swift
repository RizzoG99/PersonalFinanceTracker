//
//  TransactionItemView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct TransactionItemView: View {
    let item: TransactionModel
    let currencyCode: String
    
    init(item: TransactionModel, currencyCode: String = "EUR") {
        self.item = item
        self.currencyCode = currencyCode
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.timestamp, format: Date.FormatStyle(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(item.note)
                    .font(.body)
                Text(item.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
//                Image(systemName: item.amount > 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
//                    .foregroundColor(amountColor)
//                    .font(.caption)
                
                Text(formattedAmount)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(amountColor)
            }
        }
    }
    
    private var amountColor: Color {
        if item.amount > 0 {
            return .green // Income - positive amounts
        } else {
            return .red // Expense - negative amounts
        }
    }
    
    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        
        // Always show the absolute value for display
        return formatter.string(from: item.amount as NSDecimalNumber) ?? ""
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        List {
            TransactionItemView(
                item: TransactionModel(
                    timestamp: Date(),
                    amount: 25.50,
                    note: "Coffee and pastry",
                    category: "🍕 Food & Dining"
                )
            )
            
            TransactionItemView(
                item: TransactionModel(
                    timestamp: Date().addingTimeInterval(-3600),
                    amount: -15.99,
                    note: "Subscription fee",
                    category: "📱 Subscriptions"
                )
            )
        }
    }
}
