import Foundation

enum RecurrenceFrequency: String, CaseIterable, Sendable, Codable {
    case weekly
    case monthly
    case yearly

    var label: String {
        switch self {
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .yearly: String(localized: "Yearly")
        }
    }

    func unitLabel(for interval: Int) -> String {
        switch self {
        case .weekly: interval == 1 ? String(localized: "week") : String(localized: "weeks")
        case .monthly: interval == 1 ? String(localized: "month") : String(localized: "months")
        case .yearly: interval == 1 ? String(localized: "year") : String(localized: "years")
        }
    }

    /// "Monthly" for interval 1, "Every 3 months" otherwise. Shared by every screen that
    /// displays a rule/suggestion's cadence so the phrasing stays identical everywhere.
    func cadenceLabel(interval: Int) -> String {
        interval == 1 ? label : String(localized: "Every \(interval) \(unitLabel(for: interval))")
    }

    /// Upper bound for the interval Stepper — keeps "every N <unit>" in a sane range per
    /// frequency (e.g. not "every 52 years"). The calculator itself has no such limit.
    var maxInterval: Int {
        switch self {
        case .weekly: 52
        case .monthly: 24
        case .yearly: 10
        }
    }
}
