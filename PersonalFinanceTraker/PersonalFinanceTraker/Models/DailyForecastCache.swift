import SwiftData

@Model
final class DailyForecastCache {
    var monthKey: String        // e.g. "2026-06"
    var computedUpToDay: Int    // last calendar day with actual data
    var days: [Int]             // [1, 2, 3, ...]
    var amounts: [Double]       // cumulative spend per day, base currency

    init(monthKey: String, computedUpToDay: Int, days: [Int], amounts: [Double]) {
        self.monthKey = monthKey
        self.computedUpToDay = computedUpToDay
        self.days = days
        self.amounts = amounts
    }
}
