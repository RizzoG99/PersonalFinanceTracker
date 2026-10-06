//  RecurrenceDetector.swift
//  PersonalFinanceTraker

import Foundation
import SwiftData

struct RecurrenceSuggestion: Identifiable, Sendable {
    let id = UUID()
    let frequency: RecurrenceFrequency
    let interval: Int
    let amount: Decimal              // median of the group — the forecast for a variable bill
    let note: String                 // representative (most common) raw note from the group
    let category: String
    let currencyCode: String
    let categoryPersistentId: PersistentIdentifier?
    let occurrenceCount: Int
    /// Next expected payment: one cycle after the latest one, which anchors the rule.
    let nextDate: Date
    let occurrenceDates: [Date]      // sorted; the last anchors the rule and is its cursor
    /// Auto-record is only offered when every payment was the same amount (#188).
    var amountsIdentical = true
    /// Set for a goal transfer: the confirmed rule keeps moving money into that goal (#209).
    var goalId: UUID? = nil

    /// Strong enough evidence to start checked on the import step. Weaker suggestions are still
    /// shown, unchecked: one tap away, but never planned for by default.
    var isHighConfidence: Bool {
        let size = abs(amount)
        switch frequency {
        case .weekly, .monthly:
            return occurrenceCount >= 3 || (amountsIdentical && size >= 15)
        case .yearly:
            return occurrenceCount >= 3 && size >= 20
        }
    }

    /// Recording transactions for the user needs more than two matching payments.
    var offersAutoRecord: Bool { amountsIdentical && occurrenceCount >= 3 }

    /// A forecast-only rule (or auto-record, when the user opts in) anchored on the latest payment,
    /// which is also its cursor: that payment is covered, the next is one cycle later. Anchoring on
    /// the first payment instead put due dates on its day of the month, so a series that drifted a
    /// day earlier (26 Aug → 25 Sep) left a phantom "26 Sep" occurrence unpaid — instantly missed.
    /// ponytail: a month-end clamp (Feb 28) as the latest payment keeps later dates on the 28th.
    func ruleInput(autoRecord: Bool) -> RecurrenceRuleInput {
        RecurrenceRuleInput(
            frequency: frequency,
            interval: interval,
            startDate: occurrenceDates[occurrenceDates.count - 1],
            lastMaterializedDate: occurrenceDates.last,
            autoRecord: autoRecord && offersAutoRecord,
            amount: amount,
            note: note,
            category: category,
            currencyCode: currencyCode,
            goalId: goalId,
            categoryPersistentId: categoryPersistentId
        )
    }
}

/// A rejected suggestion ("Not fixed"), matched like an existing rule: same goal or normalised
/// note, amount within the detector's tolerance.
struct DismissedRecurrencePattern: Codable, Hashable, Sendable {
    let note: String
    let amount: Decimal
    /// Optional so patterns saved before #209 still decode.
    var goalId: UUID? = nil
}

/// Committed-spending detection (#188): finds fixed expenses in the whole history and tells
/// whether a forecast-only rule's payments have arrived.
enum RecurrenceDetector {
    /// Amounts within this fraction of each other count as the same bill.
    static let amountTolerance: Decimal = 0.15
    /// Below this a repeat is a ticket or a coffee, not a bill.
    static let minimumAmount: Decimal = 5

    static func detect(
        in inputs: [TransactionInput],
        existingRules: [RecurrenceRuleSnapshot],
        dismissed: [DismissedRecurrencePattern] = [],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [RecurrenceSuggestion] {
        // Expenses the user (or a bank file) recorded — generated rows already belong to a rule.
        let candidates = inputs.filter { $0.amount < 0 && $0.recurrenceRuleId == nil }
        let byKey = Dictionary(grouping: candidates) { commitmentKey(goalId: $0.goalId, note: $0.note) }

        var suggestions: [RecurrenceSuggestion] = []
        for (key, rows) in byKey where key.goalId != nil || !key.note.isEmpty {
            for group in amountClusters(rows) {
                // To the cent: the add form builds Decimal from a Double (8.99 → 8.99000000000000020…)
                // while CSV import parses the exact string, so the same price isn't bit-equal.
                let amounts = Set(group.map { $0.amount.roundedToCents })
                let identical = amounts.count == 1
                guard group.count >= (identical ? 2 : 3) else { continue }
                let size = abs(median(group.map(\.amount)))
                guard size >= minimumAmount else { continue }
                // Everyday spending: a merchant paid often at many prices (transit, groceries) can
                // have one price bucket that happens to look periodic. A bill is most of its payments.
                guard group.count * 2 >= rows.count else { continue }

                let dates = group.map(\.timestamp).sorted()
                guard let cadence = inferFrequency(from: dates, calendar: calendar),
                      isSupported(cadence) else { continue }
                // Two payments a year apart is the weakest evidence there is (birthday gifts pass
                // it): yearly needs a third payment, or two identical ones that look like a bill.
                // Every gap within the yearly match window, so a pattern isn't missed on day one.
                if cadence.frequency == .yearly {
                    guard group.count >= 3 || (identical && size >= 50) else { continue }
                    let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
                    guard gaps.allSatisfy({ abs($0 - 365.25) <= 14 }) else { continue }
                }

                // Recency gate: the next payment's match window must still be open, or a
                // subscription cancelled last year would be suggested (and instantly "missed").
                let lastDate = dates[dates.count - 1]
                let upcoming = RecurrenceOccurrenceCalculator.occurrenceDates(
                    frequency: cadence.frequency,
                    interval: cadence.interval,
                    startDate: lastDate,          // same anchor as ruleInput
                    ruleEndDate: nil,
                    since: lastDate,
                    through: lastDate.addingTimeInterval(400 * 86_400),   // > one yearly cycle
                    calendar: calendar
                )
                guard let nextDate = upcoming.first else { continue }
                let window = matchWindow(cadence.frequency, cadence.interval)
                guard nextDate.addingTimeInterval(window) >= today else { continue }

                let amount = median(group.map(\.amount))
                if existingRules.contains(where: { commitmentKey(goalId: $0.goalId, note: $0.note) == key && isSameAmount($0.amount, amount) })
                    || dismissed.contains(where: { commitmentKey(goalId: $0.goalId, note: $0.note) == key && isSameAmount($0.amount, amount) }) {
                    continue
                }

                suggestions.append(RecurrenceSuggestion(
                    frequency: cadence.frequency,
                    interval: cadence.interval,
                    amount: amount,
                    note: findMostCommonValue(group.map(\.note)) ?? group[0].note,
                    category: findMostCommonValue(group.map(\.category)) ?? group[0].category,
                    currencyCode: group[0].currencyCode,
                    categoryPersistentId: group.compactMap(\.categoryPersistentId).first,
                    occurrenceCount: group.count,
                    nextDate: nextDate,
                    occurrenceDates: dates,
                    amountsIdentical: identical,
                    goalId: key.goalId
                ))
            }
        }

        // Likeliest and biggest first: rent before a €6 subscription before a maybe.
        return suggestions.sorted { a, b in
            if a.isHighConfidence != b.isHighConfidence { return a.isHighConfidence }
            if abs(a.amount) != abs(b.amount) { return abs(a.amount) > abs(b.amount) }
            if a.occurrenceCount != b.occurrenceCount { return a.occurrenceCount > b.occurrenceCount }
            return a.note < b.note
        }
    }

    static func dismissalPattern(for suggestion: RecurrenceSuggestion) -> DismissedRecurrencePattern {
        DismissedRecurrencePattern(note: normalizeNote(suggestion.note), amount: suggestion.amount, goalId: suggestion.goalId)
    }

    // MARK: - Forecast-only rules

    /// How far from its due date a payment still counts for an occurrence: ±20 % of the cycle,
    /// 3–14 days (monthly ≈ ±6 days). Below half a cycle, so windows never overlap; the cap keeps
    /// a yearly bill from waiting ~2 months before "Do you still pay?".
    static func matchWindow(_ frequency: RecurrenceFrequency, _ interval: Int) -> TimeInterval {
        let cycle: Double = switch frequency {
        case .weekly: 7
        case .monthly: 30.4
        case .yearly: 365.25
        }
        return TimeInterval(min(14, max(3, Int((cycle * Double(interval) * 0.2).rounded()))) * 86_400)
    }

    /// The last occurrence of a forecast-only rule that a real expense has paid (same goal or note,
    /// amount within tolerance, date within the window — early payments included), and the
    /// amount paid for it. nil when nothing new matched.
    static func paidThrough(
        rule: RecurrenceRuleSnapshot,
        transactions: [TransactionSnapshot],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> (cursor: Date, amount: Decimal)? {
        let window = matchWindow(rule.frequency, rule.interval)
        let key = commitmentKey(goalId: rule.goalId, note: rule.note)
        var payments = transactions.filter {
            $0.amount < 0 && $0.recurrenceRuleId == nil
                && isSameAmount($0.amount, rule.amount)
                && commitmentKey(goalId: $0.goalId, note: $0.note) == key
        }
        let occurrences = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: rule.frequency,
            interval: rule.interval,
            startDate: rule.startDate,
            ruleEndDate: rule.endDate,
            since: rule.lastMaterializedDate,
            through: today.addingTimeInterval(window),
            calendar: calendar
        )
        var paid: (cursor: Date, amount: Decimal)?
        for occurrence in occurrences {
            let match = payments
                .filter { abs($0.timestamp.timeIntervalSince(occurrence)) <= window }
                .min { abs($0.timestamp.timeIntervalSince(occurrence)) < abs($1.timestamp.timeIntervalSince(occurrence)) }
            guard let match else { continue }
            payments.removeAll { $0.id == match.id }
            paid = (occurrence, match.amount)
        }
        return paid
    }

    /// The due date of a forecast-only expense rule whose payment never arrived: its match
    /// window has closed and nothing paid it. Drives "Do you still pay X?".
    static func missedOccurrence(
        rule: RecurrenceRuleSnapshot,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard !rule.autoRecord, rule.amount < 0 else { return nil }
        let window = matchWindow(rule.frequency, rule.interval)
        let due = RecurrenceOccurrenceCalculator.occurrenceDates(
            frequency: rule.frequency,
            interval: rule.interval,
            startDate: rule.startDate,
            ruleEndDate: rule.endDate,
            since: rule.lastMaterializedDate,
            through: today.addingTimeInterval(-window),
            calendar: calendar
        ).first
        return due
    }

    // MARK: - Helpers

    struct CommitmentKey: Hashable {
        let goalId: UUID?
        let note: String
    }

    /// What makes two payments the same commitment: a goal transfer is its goal (usually
    /// nameless — the "→ Goal" label lives in category, #209), anything else its normalised note.
    static func commitmentKey(goalId: UUID?, note: String) -> CommitmentKey {
        CommitmentKey(goalId: goalId, note: goalId == nil ? normalizeNote(note) : "")
    }

    static func normalizeNote(_ note: String) -> String {
        // Lowercase, keep letters only, drop month names ("affitto ottobre" → "affitto").
        let lettersOnly = String(note.lowercased().map { (c: Character) -> Character in c.isLetter ? c : " " })
        let words = lettersOnly.split(separator: " ").map { String($0) }
        return words.filter { !monthNames.contains($0) }.joined(separator: " ")
    }

    private static let monthNames: Set<String> = {
        var names = Set<String>()
        for id in ["en", "it"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: id)
            for symbols in [formatter.monthSymbols, formatter.shortMonthSymbols, formatter.standaloneMonthSymbols] {
                names.formUnion((symbols ?? []).map { $0.lowercased().filter(\.isLetter) })
            }
        }
        return names
    }()

    static func isSameAmount(_ a: Decimal, _ b: Decimal) -> Bool {
        abs(a - b) <= abs(b) * amountTolerance
    }

    /// Sorted by size, a new cluster starts whenever an amount is out of tolerance of the
    /// cluster's smallest. ponytail: greedy; a bill drifting >15 % over years splits in two —
    /// fine, the recent cluster is the one that passes the recency gate.
    private static func amountClusters(_ rows: [TransactionInput]) -> [[TransactionInput]] {
        var clusters: [[TransactionInput]] = []
        for row in rows.sorted(by: { abs($0.amount) < abs($1.amount) }) {
            if let base = clusters.last?.first, isSameAmount(row.amount, base.amount) {
                clusters[clusters.count - 1].append(row)
            } else {
                clusters.append([row])
            }
        }
        return clusters
    }

    private static func median(_ amounts: [Decimal]) -> Decimal {
        let sorted = amounts.sorted()
        return sorted[sorted.count / 2]
    }

    private struct FrequencyInfo {
        let frequency: RecurrenceFrequency
        let interval: Int
    }

    /// Only the cadences fixed expenses actually have. With 2 payments there is a single gap,
    /// which always fits *some* "every N weeks" — irregular cadences are #196.
    private static func isSupported(_ cadence: FrequencyInfo) -> Bool {
        switch cadence.frequency {
        case .weekly: cadence.interval <= 2
        case .monthly: cadence.interval <= 3
        case .yearly: cadence.interval == 1
        }
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

extension Decimal {
    /// Cent-exact, so a Double-built amount equals the same price parsed from text.
    var roundedToCents: Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}
