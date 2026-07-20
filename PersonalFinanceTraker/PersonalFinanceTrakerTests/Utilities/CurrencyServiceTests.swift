import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct CurrencyServiceTests {

    @Test func sameToSameConversionIsIdentity() {
        let sut = CurrencyService()
        // EUR rate is exactly 1.0, so EUR→EUR is precise
        #expect(sut.convert(100, from: "EUR", to: "EUR") == 100)
        // Non-EUR same-currency goes through division+multiplication — allow rounding tolerance
        let usdResult = sut.convert(200, from: "USD", to: "USD")
        #expect(abs(usdResult - 200) < Decimal(0.001))
    }

    @Test func convertToBaseFromEURIsIdentityWhenBaseIsEUR() {
        let sut = CurrencyService()
        #expect(sut.convertToBase(50, from: "EUR") == 50)
    }

    @Test func convertEURToUSDRoundTrip() {
        let sut = CurrencyService()
        let usd = sut.convert(100, from: "EUR", to: "USD")
        let back = sut.convert(usd, from: "USD", to: "EUR")
        #expect(abs(back - 100) < Decimal(0.001))
    }

    @Test func unknownCurrencyCodeReturnsAmountUnchanged() {
        let sut = CurrencyService()
        #expect(sut.convert(100, from: "XYZ", to: "EUR") == 100)
        #expect(sut.convert(100, from: "EUR", to: "XYZ") == 100)
    }

    @Test func setBaseCurrencyPersistsToUserDefaults() {
        // Isolated suite: writing app_base_currency to .standard races parallel test suites
        let suiteName = "CurrencyServiceTests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let sut = CurrencyService(defaults: suite)
        sut.setBaseCurrency("USD")
        #expect(sut.baseCurrency == "USD")
        #expect(suite.string(forKey: "app_base_currency") == "USD")
    }

    @Test func formatterHasCurrencyStyle() {
        let fmt = CurrencyService().formatter(for: "EUR")
        #expect(fmt.currencyCode == "EUR")
        #expect(fmt.numberStyle == .currency)
    }

    @Test func formattedEURCompactBelowThousandMatchesFull() {
        let value: Decimal = 999
        #expect(value.formattedEURCompact() == value.formattedEUR())
    }

    @Test func formattedEURCompactThousandsContainsK() {
        let result = Decimal(2500).formattedEURCompact()
        #expect(result.contains("K"))
    }

    @Test func formattedEURCompactMillionsContainsM() {
        let result = Decimal(1_500_000).formattedEURCompact()
        #expect(result.contains("M"))
    }

    @Test func formattedEURUsesExplicitCurrency() {
        // Explicit currency parameter: writing app_base_currency to .standard races parallel suites
        let usdFormatted = Decimal(100).formattedEUR(currency: "USD")
        #expect(usdFormatted.contains("$"))
        #expect(!usdFormatted.contains("€"))

        let gbpFormatted = Decimal(100).formattedEUR(currency: "GBP")
        #expect(gbpFormatted.contains("£"))

        let usdCompact = Decimal(2500).formattedEURCompact(currency: "USD")
        #expect(usdCompact.contains("K"))
        #expect(usdCompact.contains("$"))
    }
}
