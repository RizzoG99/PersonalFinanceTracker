import SwiftUI

struct ForecastSection: View {
    let forecast: SpendingForecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsightsSectionHeader(title: "Forecast", subtitle: "Month-end projection")
            if let fc = forecast, fc.lastThreeMonthAvg > 0 {
                ForecastCard(forecast: fc)
            } else {
                InsightsEmptyCard(message: "Not enough history for a forecast yet")
            }
        }
    }
}
