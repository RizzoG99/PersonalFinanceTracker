import SwiftUI

struct ProfileCurrencySection: View {
    @AppStorage("app_base_currency") private var baseCurrency: String = Locale.current.currency?.identifier ?? "EUR"

    private let supportedCurrencies = ["EUR", "USD", "GBP", "JPY", "AUD", "CAD", "CHF", "CNY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileSectionLabel(title: "Currency")
            Picker("Currency", selection: $baseCurrency) {
                ForEach(supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .tint(.accentIndigo)
        }
    }
}
