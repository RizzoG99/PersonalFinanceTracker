import Foundation

struct CategoryTrend: Identifiable {
    let id = UUID()
    let category: PieChartDataPoint
    let changePercent: Double
    let direction: TrendDirection
}
