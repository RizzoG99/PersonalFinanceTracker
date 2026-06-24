import Testing
import Foundation
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct CurrencyServiceTests {

    @Test func sameToSameConversionIsIdentity() {
        let sut = CurrencyService()
        #expect(sut.convert(100, from: "EUR", to: "EUR") == 100)
        #expect(sut.convert(200, from: "USD", to: "USD") == 200)
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
        defer { UserDefaults.standard.removeObject(forKey: "app_base_currency") }
        let sut = CurrencyService()
        sut.setBaseCurrency("USD")
        #expect(sut.baseCurrency == "USD")
        #expect(UserDefaults.standard.string(forKey: "app_base_currency") == "USD")
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
}
