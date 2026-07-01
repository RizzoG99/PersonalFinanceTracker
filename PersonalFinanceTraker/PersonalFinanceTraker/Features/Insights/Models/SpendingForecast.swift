import Foundation

struct SpendingForecast {
    let projectedAmount: Decimal
    let dailyPace: Decimal
    let lastThreeMonthAvg: Decimal
    let daysLeft: Int
    let dailyActuals: [DailyPoint]
}
