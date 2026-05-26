//
//  CreditScoreCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditScoreCard: View {
    let creditScore: Int
    let creditStatus: String
    let onEditScore: (Int) -> Void

    @State private var showingScoreEditor = false
    @State private var draftScore: Double = 742

    private var scoreColor: Color {
        switch creditScore {
        case 800...: return .positive
        case 740...: return .categoryTeal
        case 670...: return .categoryAmber
        default: return .negative
        }
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 20) {
                Button {
                    draftScore = Double(creditScore)
                    showingScoreEditor = true
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.bg2.opacity(0.6), lineWidth: 14)
                            .frame(width: 200, height: 200)

                        Circle()
                            .trim(from: 0, to: CGFloat(creditScore) / 850.0)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [scoreColor, .accentIndigo]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: creditScore)

                        VStack(spacing: 6) {
                            Text("\(creditScore)")
                                .font(.system(.largeTitle, weight: .bold))
                                .foregroundStyle(.textPrimary)
                                .contentTransition(.numericText())
                            Text(creditStatus)
                                .font(.headline)
                                .foregroundStyle(scoreColor)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.textDim)
                            .padding(8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Credit score \(creditScore), \(creditStatus). Tap to edit.")

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
        .sheet(isPresented: $showingScoreEditor) {
            scoreEditorSheet
                .presentationDetents([.height(220)])
                .presentationBackground { AppBackground() }
        }
    }

    private var scoreEditorSheet: some View {
        VStack(spacing: 24) {
            Text("Update Credit Score")
                .font(.headline)
                .foregroundStyle(.textPrimary)

            VStack(spacing: 8) {
                Text("\(Int(draftScore))")
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(.textPrimary)
                    .contentTransition(.numericText())

                Slider(value: $draftScore, in: 300...850, step: 1)
                    .tint(.accentIndigo)

                HStack {
                    Text("300")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                    Spacer()
                    Text("850")
                        .font(.caption)
                        .foregroundStyle(.textDim)
                }
            }
            .padding(.horizontal)

            Button {
                onEditScore(Int(draftScore))
                showingScoreEditor = false
            } label: {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentIndigo, in: .rect(cornerRadius: 16))
            }
            .padding(.horizontal)
        }
        .padding(.top, 24)
    }
}
