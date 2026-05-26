//
//  CreditScoreCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditScoreCard: View {
    let creditScore: Int
    let creditStatus: String

    var body: some View {
        GlassCard {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.bg2.opacity(0.6), lineWidth: 14)
                        .frame(width: 200, height: 200)

                    Circle()
                        .trim(from: 0, to: CGFloat(creditScore) / 850.0)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [.positive, .accentIndigo]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 6) {
                        Text("\(creditScore)")
                            .font(.system(.largeTitle, weight: .bold))
                            .foregroundStyle(.textPrimary)
                        Text(creditStatus)
                            .font(.headline)
                            .foregroundStyle(.positive)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Fair Range")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text("670 – 739")
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Excellent Range")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                        Text("800 – 850")
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
