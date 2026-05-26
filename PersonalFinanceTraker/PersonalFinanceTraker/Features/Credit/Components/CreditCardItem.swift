//
//  CreditCardItem.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditCardItem: View {
    let name: String
    let lastFour: String
    let balance: String
    let limit: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                        Text("•••• \(lastFour)")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                            .tracking(1.5)
                    }
                    Spacer()
                    Image(systemName: "creditcard.fill")
                        .font(.title)
                        .foregroundStyle(color)
                }

                Divider().opacity(0.2)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(balance)
                            .font(.headline)
                            .foregroundStyle(.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Limit")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(limit)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }
            }
        }
    }
}
