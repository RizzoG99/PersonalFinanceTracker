//
//  CreditUtilizationCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditUtilizationCard: View {
    let totalUtilization: Double

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
                        Text("€3,500")
                            .font(.headline)
                            .foregroundStyle(.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Available Credit")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text("€6,500")
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }

                ProgressView(value: totalUtilization)
                    .tint(.negative)

                HStack {
                    Text("Ideal: Keep below 30%")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                    Spacer()
                    Text("\(Int(totalUtilization * 100))%")
                        .font(.headline)
                        .foregroundStyle(.negative)
                }
            }
        }
    }
}
