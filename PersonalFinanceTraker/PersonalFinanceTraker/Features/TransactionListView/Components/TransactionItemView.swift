//
//  TransactionItemView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct TransactionItemView: View {
    let item: TransactionSnapshot

    private var categoryColor: Color {
        item.categoryColorToken.map { Color($0) } ?? CategoryInfo.info(for: item.category).color
    }

    private var categorySymbol: String {
        item.categorySystemImage ?? CategoryInfo.info(for: item.category).symbol
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
                HStack(spacing: 4) {
                    Text(item.note.isEmpty ? item.category.removingLeadingEmoji.localizedCategoryDisplay : item.note)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                    if item.recurrenceRuleId != nil {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.textDim)
                    }
                }
                if !item.note.isEmpty {
                    Text(item.category.removingLeadingEmoji.localizedCategoryDisplay)
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }

            Spacer()

            // Always-signed: income reads "+€12,34", expenses "-€12,34". Matches the
            // convention ImportResultView already uses, and means the direction of a
            // transaction never depends on colour alone.
            Text(item.amount, format: .currency(code: item.currencyCode).sign(strategy: .always()))
                .font(.headline)
                .foregroundStyle(item.amount >= 0 ? .positive : .negative)
                .privacyBlur()
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
                item: TransactionSnapshot(TransactionModel(
                    timestamp: Date(),
                    amount: 25.50,
                    note: "Coffee and pastry",
                    category: "☕ Coffee & Drinks"
                ))
            )
            TransactionItemView(
                item: TransactionSnapshot(TransactionModel(
                    timestamp: Date().addingTimeInterval(-3600),
                    amount: -15.99,
                    note: "Subscription fee",
                    category: "📱 Subscriptions"
                ))
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg0)
    }
    .preferredColorScheme(.dark)
}
