//
//  TransactionItemView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct TransactionItemView: View {
    let item: TransactionModel

    var body: some View {
        let info = CategoryInfo.info(for: item.category)
        HStack(spacing: 12) {
            GlassCard(tint: info.color.opacity(0.12), borderRadius: 12) {
                Image(systemName: info.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(info.color)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.note.isEmpty ? item.category : item.note)
                    .font(.body)
                    .foregroundColor(.textPrimary)
                Text(item.category)
                    .font(.caption)
                    .foregroundColor(.textDim)
            }

            Spacer()

            Text(formattedAmount)
                .font(.headline)
                .foregroundColor(item.amount >= 0 ? .positive : .textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = item.currencyCode
        return formatter.string(from: item.amount as NSDecimalNumber) ?? ""
    }
}

#Preview {
    NavigationStack {
        List {
            TransactionItemView(
                item: TransactionModel(
                    timestamp: Date(),
                    amount: 25.50,
                    note: "Coffee and pastry",
                    category: "☕ Coffee & Drinks"
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
        .scrollContentBackground(.hidden)
        .background(Color.bg0)
    }
    .preferredColorScheme(.dark)
}
