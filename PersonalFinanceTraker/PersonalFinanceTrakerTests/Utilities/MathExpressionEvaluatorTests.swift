import Testing
@testable import PersonalFinanceTraker

@Suite("MathExpressionEvaluator")
struct MathExpressionEvaluatorTests {

    @Test func simpleAddition() {
        #expect(MathExpressionEvaluator.evaluate("5+3") == 8)
    }

    @Test func noOperatorPrecedenceLeftToRight() {
        // Basic four-function calculator, not math notation: (2+3)×4 = 20, not 2+(3×4) = 14.
        #expect(MathExpressionEvaluator.evaluate("2+3×4") == 20)
    }

    @Test func parenthesesStillGroupExplicitly() {
        // Everything outside the parens is still flat left-to-right; the parens are the only
        // way to make a later operator apply before an earlier one.
        #expect(MathExpressionEvaluator.evaluate("2×(3+4)") == 14)
    }

    @Test func tricountReferenceExample() {
        // (500+504)×6÷8 = 753 — same result either way here (the parenthesized add is already
        // first in typing order), kept as a real-world reference check.
        #expect(MathExpressionEvaluator.evaluate("(500+504)×6÷8") == 753)
    }

    @Test func userReportedExample() {
        // 200×100+10÷20 → ((200×100)+10)÷20 = 1000.5, confirmed as the intended behavior
        // (not the 20000.5 that standard operator precedence would give).
        #expect(MathExpressionEvaluator.evaluate("200×100+10÷20") == 1000.5)
    }

    @Test func division() {
        #expect(MathExpressionEvaluator.evaluate("10÷4") == 2.5)
    }

    @Test func unaryMinus() {
        #expect(MathExpressionEvaluator.evaluate("-5+8") == 3)
    }

    @Test func decimalNumbers() {
        #expect(MathExpressionEvaluator.evaluate("1.5+2.25") == 3.75)
    }

    @Test func localeCommaDecimalSeparatorNormalized() {
        // App convention elsewhere (AmountParser, CurrencyAmountField) is comma-as-decimal.
        #expect(MathExpressionEvaluator.evaluate("1,5+2,5") == 4)
    }

    @Test func divideByZeroReturnsNil() {
        #expect(MathExpressionEvaluator.evaluate("5÷0") == nil)
    }

    @Test func trailingOperatorReturnsNil() {
        #expect(MathExpressionEvaluator.evaluate("5+") == nil)
    }

    @Test func unbalancedParenthesesReturnNil() {
        #expect(MathExpressionEvaluator.evaluate("(5+3") == nil)
        #expect(MathExpressionEvaluator.evaluate("5+3)") == nil)
    }

    @Test func emptyExpressionReturnsNil() {
        #expect(MathExpressionEvaluator.evaluate("") == nil)
    }

    @Test func garbageCharactersReturnNil() {
        #expect(MathExpressionEvaluator.evaluate("5+abc") == nil)
    }

    @Test func incidentalSpacesAreIgnored() {
        // The bubble has no space key (.decimalPad); a stray space (e.g. from a paste) merges
        // adjacent digits into one number rather than being treated as a separator.
        #expect(MathExpressionEvaluator.evaluate("5 3") == 53)
    }

    @Test func doubleDecimalPointInOneNumberReturnsNil() {
        #expect(MathExpressionEvaluator.evaluate("1.2.3+4") == nil)
    }

    @Test func emptyParenthesesReturnNil() {
        #expect(MathExpressionEvaluator.evaluate("()") == nil)
    }
}

@Suite("MathExpressionEvaluator.liveFormatted")
struct MathExpressionEvaluatorLiveFormattedTests {

    @Test func singleOperandUnchanged() {
        #expect(MathExpressionEvaluator.liveFormatted("200") == "200")
    }

    @Test func singleOperatorNotWrapped() {
        // One operation is already unambiguous — wrapping it would be a redundant outer pair.
        #expect(MathExpressionEvaluator.liveFormatted("5+3") == "5+3")
    }

    @Test func userReportedExampleWrapsAllButTheLastPair() {
        #expect(MathExpressionEvaluator.liveFormatted("200×100+10÷20") == "((200×100)+10)÷20")
    }

    @Test func trailingOperatorWithNoOperandYetStaysDangling() {
        // Still mid-keystroke: the user just tapped ÷ and hasn't typed a digit yet.
        #expect(MathExpressionEvaluator.liveFormatted("200×100+10÷") == "((200×100)+10)÷")
    }

    @Test func leadingUnaryMinusIsNotTreatedAsAnOperator() {
        #expect(MathExpressionEvaluator.liveFormatted("-5+8×2") == "(-5+8)×2")
    }

    @Test func evaluatingTheFormattedStringMatchesEvaluatingTheRawOne() {
        // The parens only ever make explicit the grouping evaluate(_:) already applies, so
        // running both through the evaluator must agree — this is the whole point of the bubble.
        let raw = "200×100+10÷20"
        let formatted = MathExpressionEvaluator.liveFormatted(raw)
        #expect(MathExpressionEvaluator.evaluate(raw) == MathExpressionEvaluator.evaluate(formatted))
    }

    @Test func emptyStringUnchanged() {
        #expect(MathExpressionEvaluator.liveFormatted("") == "")
    }
}
