//
//  IPadSection.swift
//  PersonalFinanceTraker
//

import Foundation

/// Sidebar destinations for the iPad shell.
///
/// Deliberately richer than the iPhone's three tabs: Goals and Health Score are buried inside
/// Insights on iPhone because there is no room for them, but on iPad they are things you go to,
/// so they get to be destinations.
enum IPadSection: String, Hashable, Identifiable, CaseIterable {
    case home
    case activity
    case goals
    case insights
    case healthScore
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .activity: String(localized: "Activity")
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
        case .goals: "flag"
        case .insights: "chart.line.uptrend.xyaxis"
        case .healthScore: "gauge.medium"
        case .settings: "gear"
        }
    }

    enum Group: String, Identifiable, CaseIterable {
        case overview, money, analyse

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: String(localized: "Overview")
            case .money: String(localized: "Money")
            case .analyse: String(localized: "Analyse")
            }
        }

        var sections: [IPadSection] {
            switch self {
            case .overview: [.home]
            case .money: [.activity, .goals]
            case .analyse: [.insights, .healthScore]
            }
        }
    }
}
