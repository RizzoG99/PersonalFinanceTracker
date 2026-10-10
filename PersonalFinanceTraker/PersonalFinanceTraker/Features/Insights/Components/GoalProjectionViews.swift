//
//  GoalProjectionViews.swift
//  PersonalFinanceTraker
//

import SwiftUI

/// The goal card's one-line projection (#192): when it lands, or what it takes per month.
struct GoalProjectionLine: View {
    let projection: GoalProjection

    var body: some View {
        let line = line
        Label {
            Text(line.text).foregroundStyle(line.textStyle)
        } icon: {
            Image(systemName: line.icon).foregroundStyle(line.iconStyle)
        }
        .font(.caption)
        .lineLimit(2)
        .privacyBlur()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(projection.sentence ?? line.text)
    }

    /// "Est." marks the month as a guess at the current pace, so it isn't read as the deadline.
    private var line: (text: String, icon: String, iconStyle: Color, textStyle: Color) {
        switch projection.state {
        case .complete:
            (String(localized: "Reached"), "checkmark.circle.fill", .positive, .positive)
        case .eta(let eta), .onTrack(let eta, _):
            (String(localized: "Est. \(eta.goalMonth(abbreviated: true))"), "flag.checkered", .textMid, .textMid)
        case .behind(let required, _):
            // Same warning treatment as the anomaly callout: orange triangle, readable text.
            (String(localized: "Save \(required.wholeEuros)/mo"), "exclamationmark.triangle.fill", .orange, .textMid)
        case .needsContribution(let required?, _):
            (String(localized: "Save \(required.wholeEuros)/mo"), "arrow.up.circle", .textMid, .textMid)
        case .needsContribution(nil, _):
            (String(localized: "Add a contribution"), "plus.circle", .textDim, .textDim)
        case .deadlinePassed(let eta):
            (eta.map { String(localized: "Overdue · est. \($0.goalMonth(abbreviated: true))") }
                ?? String(localized: "Overdue"), "exclamationmark.circle", .negative, .negative)
        }
    }
}

/// Goal detail's projection card: the full sentence plus where the pace comes from.
struct GoalProjectionCard: View {
    let projection: GoalProjection

    var body: some View {
        if let sentence = projection.sentence {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(sentence)
                            .font(.subheadline.bold())
                            .foregroundStyle(.textPrimary)
                    } icon: {
                        if case .behind = projection.state {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                    .privacyBlur()
                    if let caption = projection.paceCaption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.textDim)
                            .privacyBlur()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension GoalProjection {
    /// Full sentence for the detail sheet and VoiceOver; nil once the goal is reached.
    var sentence: String? {
        switch state {
        case .complete:
            nil
        case .eta(let eta):
            String(localized: "At your current pace you'll reach it in \(eta.goalMonth()).")
        case .onTrack(_, let deadline):
            String(localized: "On track to reach it by \(deadline.goalMonth()).")
        case .behind(let required, let deadline):
            String(localized: "To reach it by \(deadline.goalMonth()), save \(required.wholeEuros) a month instead of \(monthlyPace.wholeEuros).")
        case .needsContribution(let required?, let deadline?):
            String(localized: "Save \(required.wholeEuros) a month to reach it by \(deadline.goalMonth()).")
        case .needsContribution:
            String(localized: "Add a contribution to see when you'll reach it.")
        case .deadlinePassed(let eta?):
            String(localized: "Deadline passed — at your current pace you'll reach it in \(eta.goalMonth()).")
        case .deadlinePassed(nil):
            String(localized: "Deadline passed.")
        }
    }

    /// Names where the pace comes from. "Behind" already states the amount, so the
    /// caption carries it only in the other states.
    var paceCaption: String? {
        guard monthlyPace > 0, state != .complete else { return nil }
        let statesAmount = if case .behind = state { true } else { false }
        switch (source, statesAmount) {
        case (.planned, true):
            return String(localized: "Based on your recurring transfer")
        case (.planned, false):
            return String(localized: "Based on your recurring transfer of \(monthlyPace.wholeEuros) a month")
        case (.recent, true):
            return String(localized: "Based on your last 3 months")
        case (.recent, false):
            return String(localized: "Based on your last 3 months (\(monthlyPace.wholeEuros) a month)")
        }
    }
}

extension Decimal {
    /// "€286", no cents: projection amounts are already rounded up to whole euros.
    var wholeEuros: String {
        formatted(.currency(code: CurrencyService().baseCurrency).precision(.fractionLength(0)))
    }
}

private extension Date {
    /// "February" this year, "February 2027" otherwise.
    func goalMonth(abbreviated: Bool = false) -> String {
        let month: Date.FormatStyle = .dateTime.month(abbreviated ? .abbreviated : .wide)
        return Calendar.current.isDate(self, equalTo: .now, toGranularity: .year)
            ? formatted(month)
            : formatted(month.year())
    }
}
