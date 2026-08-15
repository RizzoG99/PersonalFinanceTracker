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
                Text(status.hasLoggedToday ? "Logged today" : "Log today")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text(status.hasLoggedToday ? "Keep the daily record going." : "Repeat a usual transaction or add a new one.")
                    .font(.subheadline)
                    .foregroundStyle(.textDim)
            }
            Spacer(minLength: 0)
        }
    }

    private var loggedSummary: some View {
        HStack(spacing: 12) {
            stat(value: "\(status.todayCount)", label: status.todayCount == 1 ? "entry today" : "entries today")
            stat(value: "\(status.currentStreakDays)", label: status.currentStreakDays == 1 ? "day streak" : "day streak")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !templates.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(templates) { template in
                        Button {
                            onRepeat(template)
                        } label: {
                            Label(template.displayLabel, systemImage: template.isExpense ? "minus.circle" : "plus.circle")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Button(action: onAdd) {
                Label("Add Transaction", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentIndigo)
            .controlSize(.regular)
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
            .accessibilityLabel("Dismiss reminder prompt")
        }
        .padding(.top, 2)
    }
}
