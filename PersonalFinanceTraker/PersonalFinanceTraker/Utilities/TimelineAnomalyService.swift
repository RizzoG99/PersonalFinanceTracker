//
//  TimelineAnomalyService.swift
//  PersonalFinanceTraker
//

import Foundation

struct TimelineAnomalyService {
    func annotateWithSpikes(_ raw: [ChartDataPoint]) -> [TimelineDataPoint] {
        let values = raw.map { Double(truncating: $0.expenses as NSDecimalNumber) }
        guard !values.isEmpty else { return [] }

        // ponytail: need real history before anything counts as "unusual" — otherwise
        // a lone transaction against a run of empty weeks (e.g. day one after install)
        // trivially clears mean + 1.5σ and gets flagged as a spike.
        guard values.filter({ $0 > 0 }).count >= 3 else {
            return raw.map { TimelineDataPoint(date: $0.date, period: $0.period, expenses: $0.expenses, isSpike: false) }
        }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let threshold = mean + 1.5 * variance.squareRoot()

        return zip(raw, values).map { point, val in
            TimelineDataPoint(date: point.date, period: point.period, expenses: point.expenses, isSpike: val > threshold && val > 0)
        }
    }
}
