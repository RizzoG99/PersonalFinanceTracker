//
//  GoalDetailSheet.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct GoalDetailSheet: View {
    let goal: GoalSnapshot
    let viewModel: CompassViewModel
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingFundEntry = false
    @State private var fundAmountText = ""

    private var currentAmount: Decimal { viewModel.transferTotal(for: goal) }

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(1.0, Double(truncating: (currentAmount / goal.targetAmount) as NSDecimalNumber))
    }

    private var goalColor: Color { Color(categoryToken: goal.colorToken) }
    private var isComplete: Bool { currentAmount >= goal.targetAmount }

    /// A few dark-mode category tints are intentionally bright. They need dark ink,
    /// while the remaining category tints and every light-mode tint need white ink.
    private var goalActionForeground: Color {
        if colorScheme == .dark,
           ["categoryGreen", "categoryAmber", "categoryTeal"].contains(goal.colorToken) {
            return .black
        }
        return .primaryActionForeground
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    progressRing
                    goalInfo
                    fundSection
                }
                .padding(24)
            }
            .appBackground()
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.textMid)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(goalColor)
                }
            }
        }
    }

    // MARK: - Subviews

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(goalColor.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(goalColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            VStack(spacing: 4) {
                Image(systemName: goal.iconName)
                    .font(.title2)
                    .foregroundStyle(goalColor)
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.title.bold())
                    .foregroundStyle(.textPrimary)
            }
        }
        .frame(width: 180, height: 180)
        .padding(.top, 8)
    }

    private var goalInfo: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Saved")
                        .font(.subheadline)
                        .foregroundStyle(.textDim)
                    Spacer()
                    Text(currentAmount.formattedEURCompact())
                        .font(.subheadline.bold())
                        .foregroundStyle(goalColor)
                        .privacyBlur()
                }
                HStack {
                    Text("Target")
                        .font(.subheadline)
                        .foregroundStyle(.textDim)
                    Spacer()
                    Text(goal.targetAmount.formattedEURCompact())
                        .font(.subheadline.bold())
                        .foregroundStyle(.textPrimary)
                        .privacyBlur()
                }
                if let deadline = goal.deadline {
                    Divider()
                    HStack {
                        Text("Deadline")
                            .font(.subheadline)
                            .foregroundStyle(.textDim)
                        Spacer()
                        Text(deadline, style: .date)
                            .font(.subheadline.bold())
                            .foregroundStyle(.textPrimary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fundSection: some View {
        if isComplete {
            celebrationView
        } else if showingFundEntry {
            fundEntryView
        } else {
            Button(action: { showingFundEntry = true }) {
                Label("Add Funds", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(goalActionForeground)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .glassEffect(.regular.tint(goalColor).interactive())
            }
        }
    }

    private var celebrationView: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(goalColor)
                    .symbolEffect(.bounce, value: isComplete)
                Text("Goal reached!")
                    .font(.headline.bold())
                    .foregroundStyle(goalColor)
                Text("You hit your target. Set a new goal to keep the momentum going.")
                    .font(.caption)
                    .foregroundStyle(.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var fundEntryView: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    Text("Amount")
                        .foregroundStyle(.textMid)
                    Spacer()
                    TextField("0.00", text: $fundAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.textPrimary)
                        .frame(width: 120)
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        fundAmountText = ""
                        showingFundEntry = false
                    }
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(.regular)

                    Button("Confirm") {
                        if let amount = AmountParser.parse(fundAmountText, requirePositive: true) {
                            viewModel.addFunds(amount: amount, to: goal)
                        }
                        fundAmountText = ""
                        showingFundEntry = false
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(goalActionForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.tint(goalColor).interactive())
                    .disabled(AmountParser.parse(fundAmountText, requirePositive: true) == nil)
                }
            }
        }
    }
}
