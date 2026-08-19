//
//  MathExpressionEvaluator.swift
//  PersonalFinanceTraker
//

import Foundation

/// Evaluates the simple arithmetic expressions typed into the amount field's calculator
/// bubble (+, -, ×, ÷, parentheses).
///
/// Strictly left-to-right, like a basic four-function calculator — not standard math operator
/// precedence. `2+3×4` is `(2+3)×4 = 20`, not `2+(3×4) = 14`: each operator applies to the
/// running total as soon as the next operand is typed, matching what a user watching the
/// bubble update character-by-character expects. Parentheses still group explicitly.
///
/// Hand-rolled rather than `NSExpression(format:)`: the input here is live keystrokes from
/// a keyboard toolbar, so it is very often malformed mid-entry (a trailing operator before
/// the next digit is typed, an unclosed paren). `NSExpression`'s format parser raises an
/// `NSException` on bad syntax, which Swift cannot `try/catch` — an unacceptable crash
/// surface on a money-input path. Every branch below returns `nil` instead.
enum MathExpressionEvaluator {
    /// - Parameter raw: user-facing text — "×"/"÷" and comma decimal points are normalized
    ///   internally, so callers can pass the bubble's display text as-is. Comma is treated as
    ///   a decimal point unconditionally (not just under a comma-decimal locale), matching
    ///   `AmountParser`'s existing convention elsewhere in the app — safe here since neither
    ///   character is otherwise meaningful in an arithmetic expression.
    /// - Returns: nil for anything empty, malformed, or non-finite (e.g. divide by zero).
    static func evaluate(_ raw: String) -> Double? {
        let normalized = raw
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty, let tokens = tokenize(normalized) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    private enum Token: Equatable {
        case number(Double)
        case plus, minus, multiply, divide
        case openParen, closeParen
    }

    private static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            switch chars[i] {
            case "+": tokens.append(.plus); i += 1
            case "-": tokens.append(.minus); i += 1
            case "*": tokens.append(.multiply); i += 1
            case "/": tokens.append(.divide); i += 1
            case "(": tokens.append(.openParen); i += 1
            case ")": tokens.append(.closeParen); i += 1
            case "0"..."9", ".":
                var numStr = ""
                var dotSeen = false
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    if chars[i] == "." {
                        guard !dotSeen else { return nil }  // two decimal points in one number
                        dotSeen = true
                    }
                    numStr.append(chars[i])
                    i += 1
                }
                guard let value = Double(numStr) else { return nil }
                tokens.append(.number(value))
            default:
                return nil  // unknown character — reject rather than guess
            }
        }
        return tokens
    }

    /// expression := operand (('+' | '-' | '*' | '/') operand)*   -- flat left-to-right fold,
    ///               every operator the same "precedence" (i.e. none)
    /// operand    := number | '(' expression ')' | '-' operand
    private struct Parser {
        let tokens: [Token]
        var pos = 0

        var isAtEnd: Bool { pos == tokens.count }
        var current: Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseOperand() else { return nil }
            while let tok = current, [.plus, .minus, .multiply, .divide].contains(tok) {
                pos += 1
                guard let rhs = parseOperand() else { return nil }
                switch tok {
                case .plus: value += rhs
                case .minus: value -= rhs
                case .multiply: value *= rhs
                case .divide:
                    guard rhs != 0 else { return nil }
                    value /= rhs
                default: return nil  // unreachable — filtered by the `contains` check above
                }
            }
            return value
        }

        mutating func parseOperand() -> Double? {
            guard let tok = current else { return nil }
            switch tok {
            case .minus:
                pos += 1
                guard let value = parseOperand() else { return nil }
                return -value
            case .number(let n):
                pos += 1
                return n
            case .openParen:
                pos += 1
                guard let value = parseExpression() else { return nil }
                guard current == .closeParen else { return nil }
                pos += 1
                return value
            default:
                return nil
            }
        }
    }
}

extension MathExpressionEvaluator {
    /// Live display formatting for the calculator bubble: rewrites a flat, unparenthesized
    /// expression as it's typed into the fully left-to-right-grouped form (matching Tricount),
    /// e.g. "200×100+10÷20" → "((200×100)+10)÷20" — so the grouping `evaluate(_:)` will apply
    /// is visible before the user presses "=". Every completed operator+operand pair is wrapped
    /// except the very last one — the operation currently being typed, not yet "closed" by
    /// anything after it — wrapping it too would just add a redundant outermost pair.
    ///
    /// Pure string surgery, not a re-parse into numbers: preserves exactly what was typed
    /// (including a trailing operator, or a decimal point with no digits after it yet) so it's
    /// safe to call on every keystroke. This bubble has no paren key, so `raw` itself never
    /// contains one — any "(" / ")" this produces are unambiguously decorative, safe for a
    /// caller to strip back out (see the TextField binding in TransactionFormView).
    static func liveFormatted(_ raw: String) -> String {
        guard raw.count > 1 else { return raw }
        var operands: [String] = []
        var operators: [Character] = []
        var current = ""
        for (index, ch) in raw.enumerated() {
            if "+-×÷".contains(ch), !(index == 0 && ch == "-") {
                operands.append(current)
                operators.append(ch)
                current = ""
            } else {
                current.append(ch)
            }
        }
        guard !operators.isEmpty else { return raw }  // single operand — nothing to group yet

        var result = operands[0]
        for i in 0..<(operators.count - 1) {
            result = "(\(result)\(operators[i])\(operands[i + 1]))"
        }
        return result + String(operators[operators.count - 1]) + current
    }
}
