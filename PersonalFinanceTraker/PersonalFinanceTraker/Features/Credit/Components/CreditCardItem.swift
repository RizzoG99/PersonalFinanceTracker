//
//  CreditCardItem.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditCardItem: View {
    let card: CreditCardModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var cardColor: Color {
        switch card.colorName {
        case "positive": return .positive
        case "categoryTeal": return .categoryTeal
        case "categoryPink": return .categoryPink
        case "categoryAmber": return .categoryAmber
        case "categoryPurple": return .categoryPurple
        case "negative": return .negative
        case "categoryGreen": return .categoryGreen
        default: return .accentIndigo
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                        Text("•••• \(card.lastFour)")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                            .tracking(1.5)
                    }
                    Spacer()
                    Image(systemName: "creditcard.fill")
                        .font(.title)
                        .foregroundStyle(cardColor)
                }

                Divider().opacity(0.2)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(card.balance))
                            .font(.headline)
                            .foregroundStyle(.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Limit")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(card.limit))
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }

                ProgressView(value: card.utilizationRate)
                    .tint(cardColor)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { onEdit() }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }
}
