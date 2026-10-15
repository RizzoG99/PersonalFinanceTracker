//
//  MonthlyRecapCard.swift
//  PersonalFinanceTraker
//

import SwiftUI
import UserNotifications

/// Insights' monthly recap (#193): the pay cycle that just closed in a few sentences, plus a
/// shortcut that points the explorer below at that cycle.
struct MonthlyRecapCard: View {
    let recap: MonthlyRecap
    let onShowDetail: () -> Void
    @Environment(AppSettings.self) private var appSettings
    /// Notification permission is asked once, on the first "See … in detail" tap: the cycle-end
    /// reminder defaults on, and by then the user has read what it would announce.
    @AppStorage("recapPermissionAsked") private var permissionAsked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header outside the card, like Breakdown and Patterns below it.
            VStack(alignment: .leading, spacing: 2) {
                Text("\(recap.name) recap")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text(range)
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if recap.hasComparison {
                        ForEach(Array(recap.lines.enumerated()), id: \.offset) { _, line in
                            row(line)
                        }
                    } else {
                        sentence(firstCycleSummary)
                            .foregroundStyle(.textMid)
                        Text("Comparisons start next cycle.")
                            .font(.caption)
                            .foregroundStyle(.textDim)
                    }

                    Button {
                        onShowDetail()
                        Task { await askPermissionOnce() }
                    } label: {
                        Label("See \(recap.name) in detail", systemImage: "chart.bar.xaxis")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderless)
                    .tint(.accentIndigo)
                    .frame(minHeight: 44)
                    .accessibilityHint("Shows this cycle in the breakdown below")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Pieces

    private var range: String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: recap.cycleEnd) ?? recap.cycleEnd
        return (recap.cycleStart..<last).formatted(.interval.day().month(.abbreviated))
    }

    private func row(_ line: MonthlyRecap.Line) -> some View {
        let (text, icon, color) = content(line)
        return Label {
            sentence(text).foregroundStyle(.textPrimary)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .privacyBlur()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plain(text))
    }

    /// Numbers come wrapped in `**` (see `money`/`percent`) so they stand out mid-sentence.
    private func sentence(_ markdown: String) -> some View {
        Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
            .font(.subheadline)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .privacyBlur()
    }

    private func plain(_ markdown: String) -> String {
        (try? AttributedString(markdown: markdown)).map { String($0.characters) } ?? markdown
    }

    /// Direction is in the symbol as well as the colour, so it survives Differentiate Without Color.
    private func content(_ line: MonthlyRecap.Line) -> (String, String, Color) {
        switch line {
        case .spending(nil, let previous):
            (String(localized: "You spent about the same as in \(previous)."), "equal.circle", .textMid)
        case .spending(let difference?, let previous) where difference < 0:
            (String(localized: "You spent \(money(-difference)) less than in \(previous)."), "arrow.down.circle.fill", .positive)
        case .spending(let difference?, let previous):
            (String(localized: "You spent \(money(difference)) more than in \(previous)."), "arrow.up.circle.fill", .negative)
        case .savingsRate(let from, let to):
            (String(localized: "You put aside \(percent(to)) of your income (was \(percent(from)))."),
             to > from ? "arrow.up.circle.fill" : "arrow.down.circle.fill", to > from ? .positive : .negative)
        case .mostImproved(let category, let saved):
            (String(localized: "Most improved: \(category), \(money(saved)) less."), "star.circle.fill", .positive)
        case .recurring(let change) where change > 0:
            (String(localized: "Recurring costs went up by \(money(change)) a month."), "arrow.up.circle.fill", .negative)
        case .recurring(let change):
            (String(localized: "Recurring costs went down by \(money(-change)) a month."), "arrow.down.circle.fill", .positive)
        }
    }

    private var firstCycleSummary: String {
        guard let rate = recap.savingsRate else {
            return String(localized: "You spent \(money(recap.spent)).")
        }
        return String(localized: "You spent \(money(recap.spent)) and put aside \(money(recap.saved)) (\(percent(rate)) of your income).")
    }

    /// Whole euros, like Home's sentences: cents add noise to a recap.
    private func money(_ value: Decimal) -> String {
        "**\(appSettings.hideAmounts ? "••••" : value.wholeEuros)**"
    }

    private func percent(_ value: Double) -> String {
        "**\(value.formatted(.percent.precision(.fractionLength(0))))**"
    }

    private func askPermissionOnce() async {
        guard !permissionAsked else { return }
        permissionAsked = true
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined else { return }
        // Through ReminderService so the lock overlay knows the alert is ours (no splash behind it).
        _ = await ReminderService.shared.requestPermission()
        ReminderService.shared.scheduleMonthlyRecap()
    }
}
