//
//  HabitInsightRow.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct HabitInsightRow: View {
    let observation: HabitObservation

    var body: some View {
        GlassCard(borderRadius: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentIndigo.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: observation.sfSymbol)
                        .font(.system(size: 16))
                        .foregroundStyle(.accentIndigo)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(observation.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.textPrimary)
                    Text(observation.detail)
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }

                Spacer()
            }
            // ponytail: icon is decorative, title/detail already carry the meaning — one VoiceOver stop
            .accessibilityElement(children: .combine)
        }
    }
}
