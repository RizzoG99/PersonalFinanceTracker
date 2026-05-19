//
//  CreditView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditView: View {
    @State private var creditScore: Int = 742
    @State private var creditStatus: String = "Good"
    @State private var totalUtilization: Double = 0.35

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    creditScoreCard
                    utilizationCard
                    creditCardsSection
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle("Credit")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var creditScoreCard: some View {
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
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(creditStatus)
                            .font(.headline)
                            .foregroundColor(.positive)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Fair Range")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text("670 – 739")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Excellent Range")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text("800 – 850")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var utilizationCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Credit Utilization")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Usage")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text("€3,500")
                            .font(.headline)
                            .foregroundColor(.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Available Credit")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text("€6,500")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                }

                ProgressView(value: totalUtilization)
                    .tint(.negative)

                HStack {
                    Text("Ideal: Keep below 30%")
                        .font(.caption)
                        .foregroundColor(.textDim)
                    Spacer()
                    Text("\(Int(totalUtilization * 100))%")
                        .font(.headline)
                        .foregroundColor(.negative)
                }
            }
        }
    }

    private var creditCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Credit Cards")
                .font(.headline)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                CreditCardItem(name: "Premium Rewards", lastFour: "4532", balance: "€2,100", limit: "€5,000", color: .accentIndigo)
                CreditCardItem(name: "Cashback Plus", lastFour: "8901", balance: "€1,400", limit: "€3,000", color: .positive)
                CreditCardItem(name: "Travel Card", lastFour: "2345", balance: "€0", limit: "€2,000", color: .categoryTeal)
            }
        }
    }
}

// MARK: - Subcomponents

private struct CreditCardItem: View {
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
                            .foregroundColor(.textPrimary)
                        Text("•••• \(lastFour)")
                            .font(.caption)
                            .foregroundColor(.textDim)
                            .tracking(1.5)
                    }
                    Spacer()
                    Image(systemName: "creditcard.fill")
                        .font(.title)
                        .foregroundColor(color)
                }

                Divider().opacity(0.2)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text(balance)
                            .font(.headline)
                            .foregroundColor(.negative)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Limit")
                            .font(.caption)
                            .foregroundColor(.textDim)
                        Text(limit)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
        }
    }
}

#Preview {
    CreditView()
        .preferredColorScheme(.dark)
}
