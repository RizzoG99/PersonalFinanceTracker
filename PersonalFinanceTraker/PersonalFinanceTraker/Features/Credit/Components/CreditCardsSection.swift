//
//  CreditCardsSection.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditCardsSection: View {
    let viewModel: CreditViewModel
    @State private var cardToEdit: CreditCardModel? = nil
    @State private var showingAddCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Credit Cards")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Button {
                    showingAddCard = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accentIndigo)
                }
            }
            .padding(.horizontal, 4)

            if viewModel.creditCards.isEmpty {
                GlassCard {
                    VStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.largeTitle)
                            .foregroundStyle(.textDim)
                        Text("No credit cards yet")
                            .font(.subheadline)
                            .foregroundStyle(.textDim)
                        Text("Tap + to add your first card")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.creditCards) { card in
                        CreditCardItem(
                            card: card,
                            onEdit: { cardToEdit = card },
                            onDelete: { viewModel.deleteCard(card) }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCard) {
            AddEditCreditCardSheet(viewModel: viewModel)
                .presentationBackground { AppBackground() }
        }
        .sheet(item: $cardToEdit) { card in
            AddEditCreditCardSheet(viewModel: viewModel, cardToEdit: card)
                .presentationBackground { AppBackground() }
        }
    }
}
