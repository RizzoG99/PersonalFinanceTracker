import SwiftUI

struct ForecastSection: View {
    let forecast: SpendingForecast?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Forecast")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("Month-end projection")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }
            if let fc = forecast, fc.lastThreeMonthAvg > 0 {
                ForecastCard(forecast: fc)
            } else {
                InsightsEmptyCard(message: "Not enough history for a forecast yet")
            }
        }
    }
}
