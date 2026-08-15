//
//  DailyLoggingHabitCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct DailyLoggingHabitCard: View {
    let transactionStatus: DailyLoggingStatus
    let checkInStatus: DailyCheckInStatus
    let templates: [QuickTransactionTemplate]
    let showsReminderPrompt: Bool
    let onAdd: () -> Void
    let onRepeat: (QuickTransactionTemplate) -> Void
    let onCompleteNoSpend: () -> Void
    let onUndoNoSpend: () -> Void
    let onSetReminder: () -> Void
    let onDismissReminder: () -> Void

    var body: some View {
        GlassCard(borderRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                DailyLoggingHabitHeader(state: checkInStatus.state)
                if checkInStatus.isComplete {
                    DailyCheckInSummaryView(
                        transactionStatus: transactionStatus,
                        checkInStatus: checkInStatus,
                        onUndoNoSpend: onUndoNoSpend
                    )
                } else {
                    DailyCheckInActionsView(
                        templates: templates,
                        onAdd: onAdd,
                        onRepeat: onRepeat,
                        onCompleteNoSpend: onCompleteNoSpend
                    )
                }
                if showsReminderPrompt {
                    DailyLoggingReminderPrompt(
                        onSetReminder: onSetReminder,
                        onDismissReminder: onDismissReminder
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DailyLoggingHabitHeader: View {
    let state: DailyCheckInState

    var body: some View {
        HStack(spacing: 12) {
            FinancialPulseIndicator(state: state)
            VStack(alignment: .leading, spacing: 2) {
                Text("Financial Pulse")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: LocalizedStringKey {
        switch state {
        case .pending:
            "Take a moment to check today"
        case .transactionLogged:
            "Today's check-in is complete"
        case .noSpendConfirmed:
            "No spending recorded today"
        }
    }
}

private struct DailyCheckInSummaryView: View {
    let transactionStatus: DailyLoggingStatus
    let checkInStatus: DailyCheckInStatus
    let onUndoNoSpend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DailyCheckInMetric(
                    title: transactionStatus.hasLoggedToday
                        ? "\(transactionStatus.todayCount) logged today"
                        : "No-spend day"
                )
                DailyCheckInMetric(title: "\(checkInStatus.currentStreakDays)-day check-in streak")
            }
            if checkInStatus.state == .noSpendConfirmed {
                Button("Undo check-in", systemImage: "arrow.uturn.backward", action: onUndoNoSpend)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Marks today as needing a check-in again")
            }
        }
    }
}

private struct DailyCheckInMetric: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentIndigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentIndigo.opacity(0.22), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyCheckInActionsView: View {
    let templates: [QuickTransactionTemplate]
    let onAdd: () -> Void
    let onRepeat: (QuickTransactionTemplate) -> Void
    let onCompleteNoSpend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let primaryTemplate = templates.first {
                DailyRepeatButton(template: primaryTemplate, isPrimary: true) {
                    onRepeat(primaryTemplate)
                }

                ForEach(templates.dropFirst()) { template in
                    DailyRepeatButton(template: template, isPrimary: false) {
                        onRepeat(template)
                    }
                }
            }

            DailyAddButton(isPrimary: templates.isEmpty, action: onAdd)

            Button("Nothing to log today", systemImage: "checkmark", action: onCompleteNoSpend)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Completes today's check-in without adding a transaction")
        }
    }
}

private struct DailyRepeatButton: View {
    let template: QuickTransactionTemplate
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        if isPrimary {
            repeatButton
                .buttonStyle(.borderedProminent)
        } else {
            repeatButton
                .buttonStyle(.bordered)
        }
    }

    private var repeatButton: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: template.isExpense ? "minus.circle.fill" : "plus.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    if isPrimary {
                        Text("Repeat")
                            .font(.caption)
                    }
                    Text(template.displayLabel)
                        .font(isPrimary ? .subheadline.bold() : .subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Text(template.signedDisplayAmount)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .tint(.accentIndigo)
        .controlSize(isPrimary ? .regular : .small)
        .accessibilityLabel(Text("Repeat \(template.displayLabel), \(template.signedDisplayAmount)"))
        .accessibilityInputLabels([
            Text("Repeat"),
            Text(template.displayLabel),
        ])
    }
}

private struct DailyAddButton: View {
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        if isPrimary {
            addButton
                .buttonStyle(.borderedProminent)
        } else {
            addButton
                .buttonStyle(.bordered)
        }
    }

    private var addButton: some View {
        Button(action: action) {
            Label(isPrimary ? "Add Transaction" : "Add New", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .tint(.accentIndigo)
        .controlSize(.regular)
        .accessibilityLabel(Text("Add new transaction"))
    }
}

private struct DailyLoggingReminderPrompt: View {
    let onSetReminder: () -> Void
    let onDismissReminder: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("Set daily reminder", systemImage: "bell.badge")
                .font(.subheadline)
                .foregroundStyle(.textMid)
            Spacer(minLength: 8)
            Button("Set", action: onSetReminder)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Dismiss reminder prompt", systemImage: "xmark", action: onDismissReminder)
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .padding(.top, 2)
    }
}
