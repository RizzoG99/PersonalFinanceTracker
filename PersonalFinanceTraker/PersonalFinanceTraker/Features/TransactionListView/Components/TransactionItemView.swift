//
//  TransactionItemView.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

struct TransactionItemView: View {
    let item: TransactionSnapshot
    /// Opt-in: only the Activity list mixes rows that are in a travel with rows that are
    /// not. Inside a travel's own detail sheet every row would carry it, and the Dashboard
    /// does not ask the question.
    var showsTravelBadge: Bool = false
    /// The travel `item.travelId` points at, when the caller has it to hand. Nil while the
    /// travel list is still reloading, so the badge falls back to a plain airplane with no
    /// name rather than making membership invisible mid-refresh.
    var travel: TravelSnapshot? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isInTravel: Bool { showsTravelBadge && item.travelId != nil }
    /// The travel whose name is worth printing — set only when the badge is on *and* the
    /// lookup resolved.
    private var namedTravel: TravelSnapshot? { isInTravel ? travel : nil }

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
                            // Not decorative: recurrence changes what deleting the row
                            // means. Unlabelled, VoiceOver reads the symbol's own name.
                            .accessibilityLabel("Recurring")
                    }
                }
                // Which trip, not just that there is one — the glyph alone left the user
                // unable to tell what they were about to move a row out of. Gated on
                // `isInTravel`, not `namedTravel`: while the travel list reloads the
                // lookup returns nil, and membership must not blink out of existence.
                if !item.note.isEmpty || isInTravel {
                    HStack(spacing: 4) {
                        // Kept even when the row has a custom name: that is the one case
                        // where the category is nowhere else on the row (an unnamed row
                        // shows it as the title), and two categories can share a symbol
                        // *and* a tint, so the tile does not identify it.
                        if !item.note.isEmpty {
                            Text(item.category.removingLeadingEmoji.localizedCategoryDisplay)
                        }
                        if isInTravel {
                            if !item.note.isEmpty {
                                Text(verbatim: "·").accessibilityHidden(true)
                            }
                            // Glyphs that describe *this transaction* (recurrence) live on
                            // the title line; a glyph that identifies *another object the
                            // transaction belongs to* belongs beside that object's name.
                            // On the title line it read as part of the title — and on an
                            // unnamed row the title is the category, so "Intrattenimento ⛱"
                            // looked like a category that does not exist.
                            Image(systemName: travel?.symbolName ?? "airplane")
                                .accessibilityLabel("In a travel")
                                .accessibilityHidden(namedTravel != nil)
                            if let namedTravel {
                                Text(namedTravel.name)
                                    .accessibilityLabel(Text("In travel \(namedTravel.name)"))
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.textDim)
                    // Italian runs long ("Commissioni bancarie · ⛱ Madrid") and travel
                    // names are user-chosen. A second line only where the user has already
                    // accepted taller rows everywhere.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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
