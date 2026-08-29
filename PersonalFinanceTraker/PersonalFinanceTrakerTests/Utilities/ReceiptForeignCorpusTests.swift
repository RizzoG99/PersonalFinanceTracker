//
//  ReceiptForeignCorpusTests.swift
//  PersonalFinanceTrakerTests
//
//  Runs `ReceiptParser` over the ExpressExpense SRD corpus — ~195 US restaurant receipts, shipped
//  as plain-text transcriptions in `Fixture/Receipts/Labels/`. Because those labels are already
//  clean text, this needs no Vision and no images: it measures the *parser* alone, in milliseconds.
//
//  It deliberately does not assert a per-receipt total by finding the "TOTAL" line itself — that
//  would re-implement the parser's own keyword search inside its own test and prove nothing. It
//  asserts two properties that do not depend on how the parser works:
//
//    1. the parser never returns the SUB TOTAL or the TAX amount when the receipt also prints a
//       different amount on a total line. Those are the two numbers a keyword search gets wrong,
//       they are derived here by a rule the parser does not share, and either one is a plausible
//       wrong value that would be saved unquestioned;
//    2. coverage does not regress — a change that silently stops reading English receipts fails.
//
//  The corpus is also where the English keyword tiers in `ReceiptParser` came from: the wordings
//  and their frequencies were counted here rather than guessed.
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

@Suite(.serialized)
struct ReceiptForeignCorpusTests {

    /// Late enough that the corpus's 2012–2019 dates are all *older* than the parser's two-year
    /// sane window, so every one of them clamps. That is intentional: this suite is about totals,
    /// and pinning `now` keeps it from drifting as the real clock moves.
    private static let now = DateComponents(
        calendar: .init(identifier: .gregorian), year: 2026, month: 1, day: 1
    ).date!

    private static let labels: [(name: String, lines: [String])] = {
        ReceiptFixtures.labelURLs().compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, text.components(separatedBy: .newlines))
        }
    }()

    /// Amounts the parser must never choose, read off the label by a rule of the test's own: the
    /// value on a SUB TOTAL or TAX line, kept only when the receipt prints a *different* amount on
    /// a total line. Deliberately crude — its job is to catch a known-wrong number being returned,
    /// not to define the right one.
    private static func forbiddenAmounts(in lines: [String]) -> (forbidden: Set<Decimal>, hasTotal: Bool) {
        var forbidden: Set<Decimal> = []
        var totals: Set<Decimal> = []
        for line in lines {
            guard let amount = lastAmount(in: line) else { continue }
            let upper = line.uppercased()
            if upper.contains("SUB TOTAL") || upper.contains("SUBTOTAL")
                || upper.contains("SUB-TOTAL") || upper.contains("TAX") {
                forbidden.insert(amount)
            } else if upper.contains("TOTAL") || upper.contains("AMOUNT DUE")
                        || upper.contains("BALANCE DUE") {
                totals.insert(amount)
            }
        }
        // A sub-total equal to the total (nothing taxed) is not a wrong answer to return.
        return (forbidden.subtracting(totals), !totals.isEmpty)
    }

    /// The rightmost amount on a line — on a receipt that is the price column.
    private static func lastAmount(in line: String) -> Decimal? {
        let pattern = try! NSRegularExpression(pattern: #"\d+[.,]\d{2}"#)
        let range = NSRange(line.startIndex..., in: line)
        guard let match = pattern.matches(in: line, range: range).last,
              let matched = Range(match.range, in: line) else { return nil }
        return Decimal(string: String(line[matched]).replacingOccurrences(of: ",", with: "."))
    }

    @Test(.enabled(if: !labels.isEmpty))
    func neverReturnsTheSubTotalOrTheTaxAsTheTotal() {
        var offenders: [String] = []
        var read = 0
        var silent = 0

        for label in Self.labels {
            let scan = ReceiptParser.parse(label.lines, now: Self.now)
            guard let total = scan.total else {
                if scan.totalCandidates.isEmpty { silent += 1 }
                continue
            }
            read += 1
            let (forbidden, hasTotal) = Self.forbiddenAmounts(in: label.lines)
            if hasTotal, forbidden.contains(total) {
                offenders.append("\(label.name)=\(total)")
            }
        }

        let report = """
        corpus: \(Self.labels.count) receipts — read \(read), no total \(silent)
          returned a sub-total or tax amount: \(offenders.count)
          \(offenders.prefix(30).joined(separator: " "))
        """

        #expect(offenders.isEmpty, Comment(rawValue: report))

        // Coverage floor: 164 of the 195 labels print a total-bearing line at all, so reading well
        // over half the corpus is the whole point of English support. Deliberately loose — this
        // guards against a tier or a decoy silently ceasing to match, not against inaccuracy.
        #expect(read >= 120, Comment(rawValue: report))
    }
}
