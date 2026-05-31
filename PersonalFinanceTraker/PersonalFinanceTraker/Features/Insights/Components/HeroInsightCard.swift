//
//  HeroInsightCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct HeroInsightCard: View {
    let insight: HeroInsight

    private var tintColor: Color {
        switch insight.trendDirection {
        case .down:  return .positive
        case .up:    return .negative
        case .flat:  return .accentIndigo
        }
    }

    private var sfSymbol: String {
        switch insight.trendDirection {
        case .up:   return "arrow.up.circle.fill"
        case .down: return "arrow.down.circle.fill"
        case .flat: return "equal.circle.fill"
        }
    }

    var body: some View {
        GlassCard(tint: tintColor) {
            HStack(spacing: 16) {
                Image(systemName: sfSymbol)
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))

                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(insight.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()
            }
        }
    }
}
