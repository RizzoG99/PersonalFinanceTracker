//
//  HabitLoggingService.swift
//  PersonalFinanceTraker
//

import Foundation

struct DailyLoggingStatus: Equatable, Sendable, Codable {
    let hasLoggedToday: Bool
    let todayCount: Int
    let currentStreakDays: Int
}

struct QuickTransactionTemplate: Identifiable, Equatable, Sendable, Codable {
    var id: String {
        [
            amount.description,
            category,
            note,
            currencyCode,
        ].joined(separator: "|")
    }

    let amount: Decimal
    let note: String
    let category: String
    let currencyCode: String
    let lastUsed: Date
    let frequency: Int

    var isExpense: Bool { amount < 0 }
    var amountMagnitude: Decimal { abs(amount) }
    var amountMagnitudeDouble: Double {
        (amountMagnitude as NSDecimalNumber).doubleValue
    }

    var displayLabel: String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote.isEmpty ? category : trimmedNote
    }

    var signedDisplayAmount: String {
        amount.formatted(.currency(code: currencyCode).sign(strategy: .always()))
    }
}

struct HabitLoggingService {
    static func computeStatus(
        transactions: [TransactionSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyLoggingStatus {
        let loggedDays = Set(transactions.map { calendar.startOfDay(for: $0.timestamp) })
        let today = calendar.startOfDay(for: now)
        let todayCount = transactions.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }.count

        var streak = 0
        var day = today
        while loggedDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }

        return DailyLoggingStatus(
            hasLoggedToday: todayCount > 0,
            todayCount: todayCount,
            currentStreakDays: streak
        )
    }

    static func quickTemplates(
        from transactions: [TransactionSnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [QuickTransactionTemplate] {
        guard limit > 0 else { return [] }
        let startDate = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        var grouped: [TemplateKey: TemplateStats] = [:]

        for transaction in transactions where transaction.timestamp >= startDate {
            guard !isTransfer(transaction) else { continue }
            guard transaction.amount != 0 else { continue }

            let key = TemplateKey(
                amount: transaction.amount,
                category: transaction.category,
                note: transaction.note.trimmingCharacters(in: .whitespacesAndNewlines),
                currencyCode: transaction.currencyCode
            )
            var stats = grouped[key] ?? TemplateStats(
                frequency: 0,
                loggedDayKeys: [],
                lastUsed: .distantPast
            )
            stats.frequency += 1
            stats.loggedDayKeys.insert(calendar.startOfDay(for: transaction.timestamp))
            stats.lastUsed = max(stats.lastUsed, transaction.timestamp)
            grouped[key] = stats
        }

        // One-offs and same-day duplicates are not reliable repeat suggestions.
        return grouped
            .filter { $0.value.loggedDayKeys.count >= 2 }
            .map { key, stats in
                QuickTransactionTemplate(
                    amount: key.amount,
                    note: key.note,
                    category: key.category,
                    currencyCode: key.currencyCode,
                    lastUsed: stats.lastUsed,
                    frequency: stats.frequency
                )
            }
            .sorted {
                if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
                return $0.lastUsed > $1.lastUsed
            }
            .prefix(limit)
            .map { $0 }
    }

    static func shouldShowReminderPrompt(
        transactions: [TransactionSnapshot],
        remindersEnabled: Bool,
        promptDismissed: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard !remindersEnabled, !promptDismissed else { return false }
        let loggedDays = Set(transactions.map { calendar.startOfDay(for: $0.timestamp) })
        return loggedDays.count >= 3
    }

    private static func isTransfer(_ transaction: TransactionSnapshot) -> Bool {
        if transaction.goalId != nil { return true }
        return looksLikeTransfer(transaction.category) || looksLikeTransfer(transaction.note)
    }

    private static func looksLikeTransfer(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("transfer") || lower.contains("trasferim") || lower.contains("giro")
    }

    private struct TemplateKey: Hashable {
        let amount: Decimal
        let category: String
        let note: String
        let currencyCode: String
    }

    private struct TemplateStats {
        var frequency: Int
        var loggedDayKeys: Set<Date>
        var lastUsed: Date
    }
}
