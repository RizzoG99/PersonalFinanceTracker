import Testing
@testable import PersonalFinanceTraker
import Foundation

@Suite
struct AmountParserTests {

    @Test func parsesPlainDigits() {
        #expect(AmountParser.parse("350") == 350)
    }

    @Test func normalizesCommaToPeriod() {
        #expect(AmountParser.parse("5,50") == 5.5)
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
