//  RecurrenceDetector.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

struct RecurrenceSuggestion: Identifiable, Sendable {
    let id = UUID()
    let frequency: RecurrenceFrequency
    let interval: Int
    let amount: Decimal
    let note: String                 // representative (most common) raw note from the group
    let category: String
    let currencyCode: String
    let categoryPersistentId: PersistentIdentifier?
    let occurrenceCount: Int
    let nextDate: Date               // becomes RecurrenceRuleInput.startDate
    let occurrenceDates: [Date]      // rows that formed this group, so import can backfill recurrenceRuleId
}

enum RecurrenceDetector {
    static func detect(
        in inputs: [TransactionInput],
        existingRules: [RecurrenceRuleSnapshot],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [RecurrenceSuggestion] {
        // 1. Group by (normalizedNote, amount)
        let groups = groupTransactions(inputs)

        // 2. Drop groups with fewer than 3 rows and infer frequency
        var suggestions: [RecurrenceSuggestion] = []

        for (key, group) in groups {
            guard group.count >= 3 else { continue }

            let dates = group.map { $0.timestamp }.sorted()

            // 3. Infer frequency from day gaps
            guard let frequencyInfo = inferFrequency(from: dates, calendar: calendar) else {
                continue
            }

            // 4. Calculate nextDate (must be strictly after max(lastDate, today))
            guard let nextDate = calculateNextDate(
                from: dates,
                frequency: frequencyInfo.frequency,
                interval: frequencyInfo.interval,
                today: today,
                calendar: calendar
            ) else {
                continue
            }

            // 5. Filter out matches with existing rules
            if isMatchingExistingRule(
                note: key.normalizedNote,
                amount: key.amount,
                frequency: frequencyInfo.frequency,
                existingRules: existingRules
            ) {
                continue
            }

            // Find the most common raw note and category in the group
            let mostCommonNote = findMostCommonValue(group.map { $0.note }) ?? key.normalizedNote
            let mostCommonCategory = findMostCommonValue(group.map { $0.category }) ?? group.first!.category

            let suggestion = RecurrenceSuggestion(
                frequency: frequencyInfo.frequency,
                interval: frequencyInfo.interval,
                amount: key.amount,
                note: mostCommonNote,
                category: mostCommonCategory,
                currencyCode: group.first!.currencyCode,
                categoryPersistentId: group.first!.categoryPersistentId,
                occurrenceCount: group.count,
                nextDate: nextDate,
                occurrenceDates: dates
            )

            suggestions.append(suggestion)
        }

        // 6. Sort by occurrenceCount descending, then by note ascending
        return suggestions.sorted { a, b in
            if a.occurrenceCount != b.occurrenceCount {
                return a.occurrenceCount > b.occurrenceCount
            }
            return a.note < b.note
        }
    }

    // MARK: - Private Helpers

    private struct GroupKey: Hashable {
        let normalizedNote: String
        let amount: Decimal
    }

    private static func normalizeNote(_ note: String) -> String {
        // Lowercase, remove digits and punctuation, collapse and trim whitespace
        let lowercased = note.lowercased()
        let cleaned = lowercased.filter { $0.isLetter || $0.isWhitespace }
        let collapsed = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed
    }

    private static func groupTransactions(
        _ inputs: [TransactionInput]
    ) -> [GroupKey: [TransactionInput]] {
        var groups: [GroupKey: [TransactionInput]] = [:]

        for input in inputs {
            let key = GroupKey(normalizedNote: normalizeNote(input.note), amount: input.amount)
            groups[key, default: []].append(input)
        }

        return groups
    }

    private struct FrequencyInfo {
        let frequency: RecurrenceFrequency
        let interval: Int
    }

    private static func inferFrequency(
        from dates: [Date],
        calendar: Calendar
    ) -> FrequencyInfo? {
        guard dates.count >= 2 else { return nil }

        // Compute day-gaps between consecutive dates
        var gaps: [Int] = []
        for i in 1..<dates.count {
            let components = calendar.dateComponents([.day], from: dates[i - 1], to: dates[i])
            if let dayDiff = components.day, dayDiff > 0 {
                gaps.append(dayDiff)
            }
        }

        guard !gaps.isEmpty else { return nil }

        // Compute median gap. For even-length arrays, this takes the upper-middle value
        // (e.g., for [1, 2, 3, 4], it returns 3). This is acceptable behavior for gap analysis.
        let sortedGaps = gaps.sorted()
        let medianGap = sortedGaps[sortedGaps.count / 2]

        // Check ±20% tolerance on individual gaps
        let tolerance = Double(medianGap) * 0.2
        let minGap = Double(medianGap) - tolerance
        let maxGap = Double(medianGap) + tolerance

        // Reject if any gap deviates more than 20%
        for gap in gaps {
            if Double(gap) < minGap || Double(gap) > maxGap {
                return nil
            }
        }

        // Special case: monthly for 28-31 day gaps (month-end clamping)
        if medianGap >= 28 && medianGap <= 31 {
            return FrequencyInfo(frequency: .monthly, interval: 1)
        }

        let medianDouble = Double(medianGap)

        // Check candidates in order of coarseness (yearly → monthly → weekly).
        // Calendar-anchored frequencies (yearly/monthly) better preserve real-world patterns
        // than day-of-week-anchored ones (weekly), and match user expectations ("every 3 months"
        // rather than "every 13 weeks" for the same gap). Accept the first candidate within 10% error.

        // Yearly: expected gap = 365.25 * n, n = round(median / 365.25)
        let yearlyDays = 365.25
        let yearlyInterval = Int((medianDouble / yearlyDays).rounded())
        if yearlyInterval >= 1 && yearlyInterval <= RecurrenceFrequency.yearly.maxInterval {
            let expectedGap = yearlyDays * Double(yearlyInterval)
            let relativeError = abs(medianDouble - expectedGap) / expectedGap
            if relativeError <= 0.10 {
                return FrequencyInfo(frequency: .yearly, interval: yearlyInterval)
            }
        }

        // Monthly: expected gap = 30.4 * n, n = round(median / 30.4)
        let monthlyDays = 30.4
        let monthlyInterval = Int((medianDouble / monthlyDays).rounded())
        if monthlyInterval >= 1 && monthlyInterval <= RecurrenceFrequency.monthly.maxInterval {
            let expectedGap = monthlyDays * Double(monthlyInterval)
            let relativeError = abs(medianDouble - expectedGap) / expectedGap
            if relativeError <= 0.10 {
                return FrequencyInfo(frequency: .monthly, interval: monthlyInterval)
            }
        }

        // Weekly: expected gap = 7 * n, n = round(median / 7)
        let weeklyInterval = Int((medianDouble / 7).rounded())
        if weeklyInterval >= 1 && weeklyInterval <= RecurrenceFrequency.weekly.maxInterval {
            let expectedGap = Double(weeklyInterval * 7)
            let relativeError = abs(medianDouble - expectedGap) / expectedGap
            if relativeError <= 0.10 {
                return FrequencyInfo(frequency: .weekly, interval: weeklyInterval)
            }
        }

        return nil
    }

    private static func calculateNextDate(
        from dates: [Date],
        frequency: RecurrenceFrequency,
        interval: Int,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        guard let firstDate = dates.first, let lastDate = dates.last else { return nil }

        // nextDate must be strictly after max(lastDate, today) to prevent backfill duplicates.
        // A 10-year lookahead from the cutoff is sufficient for all valid frequency/interval pairs.
        // If occurrences returns empty (shouldn't happen), the group is dropped cleanly.
        let cutoff = lastDate > today ? lastDate : today
        let farFuture = calendar.date(byAdding: .year, value: 10, to: cutoff) ?? cutoff.addingTimeInterval(365 * 24 * 3600)
        let occurrences = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: frequency,
            interval: interval,
            startDate: firstDate,
            ruleEndDate: nil,
            since: cutoff,
            through: farFuture,
            calendar: calendar
        )

        return occurrences.first
    }

    private static func isMatchingExistingRule(
        note: String,
        amount: Decimal,
        frequency: RecurrenceFrequency,
        existingRules: [RecurrenceRuleSnapshot]
    ) -> Bool {
        existingRules.contains { rule in
            normalizeNote(rule.note) == note &&
            rule.amount == amount &&
            rule.frequency == frequency
        }
    }

    private static func findMostCommonValue(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        // Sort by count descending, then lexicographically by key for deterministic tie-breaking
        let sorted = counts.sorted { a, b in
            if a.value != b.value {
                return a.value > b.value
            }
            return a.key < b.key
        }
        return sorted.first?.key
    }
}

// ponytail: exact-amount grouping and naive note normalization; fuzzy matching / variable-amount bills if the naive version visibly misses real imports
