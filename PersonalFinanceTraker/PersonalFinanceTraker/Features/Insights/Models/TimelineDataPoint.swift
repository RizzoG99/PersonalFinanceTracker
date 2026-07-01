import Foundation

struct TimelineDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let period: String
    let expenses: Decimal
    let isSpike: Bool

    var expenseValue: Double { Double(truncating: expenses as NSDecimalNumber) }
}
