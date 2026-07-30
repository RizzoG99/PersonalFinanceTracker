//
//  InsightsKPICard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct InsightsKPICard: View {
    let title: LocalizedStringKey
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.textDim)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 90)
        }
    }
}
