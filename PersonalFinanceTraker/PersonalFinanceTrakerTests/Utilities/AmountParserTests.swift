import Testing
@testable import PersonalFinanceTraker
import Foundation

@Suite
struct AmountParserTests {

    @Test func parsesPlainDigits() {
        #expect(AmountParser.parse("350") == 350)
    }

    @Test func parsesItalianDecimalAndGroupingSeparators() {
        #expect(AmountParser.parse("1.234,56", locale: Locale(identifier: "it_IT")) == 1234.56)
    }

    @Test func parsesUSDecimalAndGroupingSeparators() {
        #expect(AmountParser.parse("1,234.56", locale: Locale(identifier: "en_US")) == 1234.56)
    }

    @Test func parsesPeriodDecimalFromExternalKeyboardInItalianLocale() {
        #expect(AmountParser.parse("1100.45", locale: Locale(identifier: "it_IT")) == 1100.45)
    }

    @Test func parsesCommaDecimalFromExternalKeyboardInUSLocale() {
        #expect(AmountParser.parse("1100,45", locale: Locale(identifier: "en_US")) == 1100.45)
    }

    @Test func normalizesExternalKeyboardDecimalKeyWhileTyping() {
        #expect(AmountParser.sanitizedInput("1100.45", locale: Locale(identifier: "it_IT")) == "1100,45")
    }

    @Test func stripsInvalidCharactersExtraSeparatorsAndExcessFractionDigits() {
        #expect(AmountParser.sanitizedInput("1.100&10", locale: Locale(identifier: "it_IT")) == "1,10")
    }

    @Test func preservesValidLocalizedGroupingDuringFocusChanges() {
        #expect(AmountParser.sanitizedInput("2.000.000,00", locale: Locale(identifier: "it_IT")) == "2.000.000,00")
    }

    @Test func trimsWhitespace() {
        #expect(AmountParser.parse("  350  ") == 350)
    }

    @Test func emptyStringReturnsNil() {
        #expect(AmountParser.parse("") == nil)
    }

    @Test func garbageReturnsNil() {
        #expect(AmountParser.parse("abc") == nil)
    }

    @Test func permissiveModeAcceptsZero() {
        #expect(AmountParser.parse("0") == 0)
    }

    @Test func permissiveModeAcceptsNegative() {
        #expect(AmountParser.parse("-5") == -5)
    }

    @Test func requirePositiveRejectsZero() {
        #expect(AmountParser.parse("0", requirePositive: true) == nil)
    }

    @Test func requirePositiveRejectsNegative() {
        #expect(AmountParser.parse("-5", requirePositive: true) == nil)
    }

    @Test func requirePositiveAcceptsPositive() {
        #expect(AmountParser.parse("5", requirePositive: true) == 5)
    }

    @Test func formatsAsEURCurrency() {
        #expect(AmountParser.format(111.10, currencyCode: "EUR") == Decimal(111.10).formatted(.currency(code: "EUR")))
    }

    @Test func formatDefaultsToEUR() {
        #expect(AmountParser.format(50) == Decimal(50).formatted(.currency(code: "EUR")))
    }
}
