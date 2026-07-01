import Foundation

struct DailyPoint: Identifiable {
    let id = UUID()
    let day: Int
    let cumulative: Decimal
}
