//
//  IPadSection.swift
//  PersonalFinanceTraker
//

import Foundation

/// Sidebar destinations for the iPad shell.
///
/// Grouped like the iPhone's four tabs (Home · Activity · Plan · Insights, #187), but richer:
/// what iPhone stacks on one Plan page or inside Insights — Recurring, Budgets, Goals, Health
/// Score — gets its own destination here, because on iPad there is room to go to each.
enum IPadSection: String, Hashable, Identifiable, CaseIterable {
    case home
    case activity
    case recurring
    case budgets
    case goals
    case insights
    case healthScore
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .activity: String(localized: "Activity")
        case .recurring: String(localized: "Recurring")
        case .budgets: String(localized: "Budgets")
        case .goals: String(localized: "Goals")
        case .insights: String(localized: "Insights")
        case .healthScore: String(localized: "Health Score")
        case .settings: String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .activity: "list.bullet.rectangle"
        case .recurring: "repeat"
        case .budgets: "chart.bar"
        case .goals: "flag"
        case .insights: "chart.line.uptrend.xyaxis"
        case .healthScore: "gauge.medium"
        case .settings: "gear"
        }
    }

    enum Group: String, Identifiable, CaseIterable {
        case top, plan, insights

        var id: String { rawValue }

        /// nil for `top`: Home and Activity are single destinations, so a heading over them
        /// would just repeat their names.
        var title: String? {
            switch self {
            case .top: nil
            case .plan: String(localized: "Plan")
            case .insights: String(localized: "Insights")
            }
        }

        var sections: [IPadSection] {
            switch self {
            case .top: [.home, .activity]
            case .plan: [.recurring, .budgets, .goals]
            case .insights: [.insights, .healthScore]
            }
        }
    }
}
