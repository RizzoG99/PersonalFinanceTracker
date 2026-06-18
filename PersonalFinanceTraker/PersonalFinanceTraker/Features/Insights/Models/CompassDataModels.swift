//
//  CompassDataModels.swift
//  PersonalFinanceTraker
//

import Foundation

// MARK: - Trend

enum TrendDirection {
    case up, down, flat
}

// MARK: - Hero Insight

struct HeroInsight {
    let title: String
    let subtitle: String
    let emoji: String
    let trendDirection: TrendDirection
}

// MARK: - Health Score

struct ScoreComponent: Identifiable {
    let id = UUID()
    let name: String
    let score: Int
    let max: Int
    let explanation: String
    let tip: String?
}

struct HealthScore {
    let score: Int
    let label: String
    let components: [ScoreComponent]
}

// MARK: - Timeline

struct TimelineDataPoint: Identifiable {
    let id = UUID()
    let period: String
    let expenses: Decimal
    let isSpike: Bool
}

// MARK: - Category Trend

struct CategoryTrend: Identifiable {
    let id = UUID()
    let category: PieChartDataPoint
    let changePercent: Double
    let direction: TrendDirection
}

// MARK: - Habit

struct HabitObservation: Identifiable {
    let id = UUID()
    let sfSymbol: String
    let title: String
    let detail: String
}

// MARK: - Forecast

struct SpendingForecast {
    let projectedAmount: Decimal
    let dailyPace: Decimal
    let lastThreeMonthAvg: Decimal
    let daysLeft: Int
}
