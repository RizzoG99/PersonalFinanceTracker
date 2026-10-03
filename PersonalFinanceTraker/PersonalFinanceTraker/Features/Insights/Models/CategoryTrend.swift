import Foundation

struct CategoryTrend: Identifiable {
    let id = UUID()
    let category: PieChartDataPoint
    let changePercent: Double
    let direction: TrendDirection
    let isNew: Bool

    /// One trend per `current` slice, Δ against the same category in `previous` (matched by name).
    /// A category with nothing in `previous` is "new" rather than an infinite % change.
    static func compare(current: [PieChartDataPoint], previous: [PieChartDataPoint]) -> [CategoryTrend] {
        let previousByName = Dictionary(previous.map { ($0.category, $0.amount) }, uniquingKeysWith: { a, _ in a })
        return current.map { cat in
            let prev = previousByName[cat.category] ?? 0
            let change = prev > 0 ? Double(truncating: ((cat.amount - prev) / prev * 100) as NSDecimalNumber) : 0
            let direction: TrendDirection = change > 5 ? .up : change < -5 ? .down : .flat
            return CategoryTrend(category: cat, changePercent: change, direction: direction, isNew: prev == 0 && cat.amount > 0)
        }
    }
}
