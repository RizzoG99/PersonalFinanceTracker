//
//  StatCard.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 19/05/2026.
//


import SwiftUI
import SwiftData

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        GlassCard(tint: color.opacity(0.1), borderRadius: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(color)
                }

                Text(value)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
