//
//  TimelineAnomalyService.swift
//  PersonalFinanceTraker
//

import Foundation

struct TimelineAnomalyService {
    func annotateWithSpikes(_ raw: [ChartDataPoint]) -> [TimelineDataPoint] {
        let values = raw.map { Double(truncating: $0.expenses as NSDecimalNumber) }
        guard !values.isEmpty else { return [] }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let threshold = mean + 1.5 * variance.squareRoot()

        return zip(raw, values).map { point, val in
            TimelineDataPoint(period: point.period, expenses: point.expenses, isSpike: val > threshold && val > 0)
        }
    }
}
