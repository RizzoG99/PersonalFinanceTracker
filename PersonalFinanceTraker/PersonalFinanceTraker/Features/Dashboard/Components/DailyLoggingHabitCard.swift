//
//  DailyLoggingHabitCard.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct DailyLoggingHabitCard: View {
    let status: DailyLoggingStatus
    let templates: [QuickTransactionTemplate]
    let showsReminderPrompt: Bool
    let onAdd: () -> Void
    let onRepeat: (QuickTransactionTemplate) -> Void
    let onSetReminder: () -> Void
    let onDismissReminder: () -> Void

    var body: some View {
        GlassCard(borderRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if status.hasLoggedToday {
                    loggedSummary
                } else {
                    quickActions
                }
                if showsReminderPrompt {
                    reminderPrompt
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: status.hasLoggedToday ? "checkmark.circle.fill" : "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(status.hasLoggedToday ? .positive : .accentIndigo)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily log")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text(status.hasLoggedToday ? "Logged today" : "No transaction logged today")
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var loggedSummary: some View {
        HStack(spacing: 12) {
            summaryChip {
                Text("\(status.todayCount) logged today")
            }
            summaryChip {
                Text("\(status.currentStreakDays)-day streak")
            }
        }
    }

    private func summaryChip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.subheadline.bold())
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentIndigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentIndigo.opacity(0.22), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let primaryTemplate = templates.first {
                Button {
                    onRepeat(primaryTemplate)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: primaryTemplate.isExpense ? "minus.circle.fill" : "plus.circle.fill")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Repeat")
                                .font(.caption)
                            Text(primaryTemplate.displayLabel)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .layoutPriority(1)
                        Spacer(minLength: 8)
                        Text(primaryTemplate.signedDisplayAmount)
                            .font(.subheadline)
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentIndigo)
                .accessibilityLabel(Text("Repeat \(primaryTemplate.displayLabel), \(primaryTemplate.signedDisplayAmount)"))
                .accessibilityInputLabels([
                    Text("Repeat"),
                    Text(primaryTemplate.displayLabel),
                ])

                ForEach(templates.dropFirst()) { template in
                    Button {
                        onRepeat(template)
                    } label: {
                        HStack(spacing: 8) {
                            Label(template.displayLabel, systemImage: template.isExpense ? "minus.circle" : "plus.circle")
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            Text(template.signedDisplayAmount)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(Text("Repeat \(template.displayLabel), \(template.signedDisplayAmount)"))
                    .accessibilityInputLabels([
                        Text("Repeat"),
                        Text(template.displayLabel),
                    ])
                }
            }

            if templates.isEmpty {
                Button(action: onAdd) {
                    Label("Add Transaction", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentIndigo)
                .controlSize(.regular)
                .accessibilityLabel(Text("Add new transaction"))
            } else {
                Button(action: onAdd) {
                    Label("Add New", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel(Text("Add new transaction"))
            }
        }
    }

    private var reminderPrompt: some View {
        HStack(spacing: 8) {
            Label("Set daily reminder", systemImage: "bell.badge")
                .font(.subheadline)
                .foregroundStyle(.textMid)
            Spacer(minLength: 8)
            Button("Set") { onSetReminder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button {
                onDismissReminder()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss reminder prompt"))
        }
        .padding(.top, 2)
    }
}
