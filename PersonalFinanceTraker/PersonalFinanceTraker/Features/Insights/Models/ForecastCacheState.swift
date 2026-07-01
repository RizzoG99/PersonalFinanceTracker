import Foundation

struct ForecastCacheState {
    let monthKey: String
    let computedUpToDay: Int
    let days: [Int]
    let amounts: [Double]
}
