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

    private var displayTitle: String {
        switch insight.trendDirection {
        case .down:  return "Under last month's pace"
        case .up:    return "Watch your pace"
        case .flat:  return insight.title
        }
    }

    private var pillText: String? {
        guard let match = insight.title.firstMatch(of: /(\d+)%/) else { return nil }
        let pct = match.1
        switch insight.trendDirection {
        case .down:  return "↓ \(pct)%"
        case .up:    return "↑ \(pct)%"
        case .flat:  return nil
        }
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: sfSymbol)
                    .font(.system(size: 32))
                    .foregroundStyle(tintColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.textPrimary)
                    Text(insight.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                }

                Spacer()

                if let pill = pillText {
                    Text(pill)
                        .font(.caption.bold())
                        .foregroundStyle(tintColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(tintColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}
