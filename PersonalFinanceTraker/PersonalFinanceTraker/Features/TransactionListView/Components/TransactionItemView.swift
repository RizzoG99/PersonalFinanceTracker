//
//  TransactionItemView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct TransactionItemView: View {
    let item: TransactionModel

    private var categoryColor: Color {
        item.categoryModel?.categoryColor ?? CategoryInfo.info(for: item.category).color
    }

    private var categorySymbol: String {
        item.categoryModel?.systemImage ?? CategoryInfo.info(for: item.category).symbol
    }

    var body: some View {
        HStack(spacing: 12) {
            GlassCard(tint: categoryColor.opacity(0.12), borderRadius: 12) {
                Image(systemName: categorySymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(categoryColor)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.note.isEmpty ? item.category : item.note)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                Text(item.category)
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }

            Spacer()

            Text(item.amount, format: .currency(code: item.currencyCode))
                .font(.headline)
                .foregroundStyle(item.amount >= 0 ? .positive : .textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
