//
//  CreditCardsSection.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditCardsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Credit Cards")
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                CreditCardItem(name: "Premium Rewards", lastFour: "4532", balance: "€2,100", limit: "€5,000", color: .accentIndigo)
                CreditCardItem(name: "Cashback Plus", lastFour: "8901", balance: "€1,400", limit: "€3,000", color: .positive)
                CreditCardItem(name: "Travel Card", lastFour: "2345", balance: "€0", limit: "€2,000", color: .categoryTeal)
            }
        }
    }
}
