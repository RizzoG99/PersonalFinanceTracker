//
//  CreditUtilizationCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditUtilizationCard: View {
    let totalBalance: Decimal
    let totalAvailable: Decimal
    let totalUtilization: Double

    var utilizationColor: Color {
        switch totalUtilization {
        case ..<0.3: return .positive
        case ..<0.5: return .categoryAmber
        default: return .negative
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Credit Utilization")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Usage")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(totalBalance))
                            .font(.headline)
                            .foregroundStyle(.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Available Credit")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text(formatEUR(totalAvailable))
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }

                ProgressView(value: totalUtilization)
                    .tint(utilizationColor)

                HStack {
                    Text("Ideal: Keep below 30%")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                    Spacer()
                    Text("\(Int(totalUtilization * 100))%")
                        .font(.headline)
                        .foregroundStyle(utilizationColor)
                }
            }
        }
    }
}
