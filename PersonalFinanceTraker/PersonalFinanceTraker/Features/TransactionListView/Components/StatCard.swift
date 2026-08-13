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
    let label: LocalizedStringKey
    let value: String
    let color: Color

    private let cornerRadius: CGFloat = 16

    var body: some View {
        GlassCard(tint: color.opacity(0.1), borderRadius: cornerRadius) {
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
                    .privacyBlur()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The fill is only a 10% tint, which reads clearly against near-black or
        // against a white card, but softens on a pale page — on Activity these sit
        // directly on the background, where the Dashboard gives them a white card
        // to stand on. An edge doesn't depend on what is behind it, and it touches
        // neither the fill nor the text on it, so it costs nothing in contrast.
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        }
    }
}
