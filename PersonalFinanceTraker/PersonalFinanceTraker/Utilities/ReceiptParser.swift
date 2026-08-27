//
//  ReceiptParser.swift
//  PersonalFinanceTraker
//
//  Parses Vision-recognized text lines from an Italian receipt into a best-effort
//  amount/date/merchant guess. Pure Swift, no SwiftUI/SwiftData — testable against
//  fixture line arrays without a camera. See docs/features/2026-08-27-scan-receipt-autofill.md.
//

import Foundation

/// The outcome of parsing one receipt's recognized text lines.
struct ReceiptScan: Equatable {
    /// The chosen total, when exactly one keyword line matched (or one keyword
    /// value repeated across multiple lines that all agree).
    var total: Decimal?
    /// Populated only when the total is ambiguous — multiple *disagreeing*
    /// keyword-tagged amounts were found. The form surfaces these as chips
    /// instead of guessing; `total` stays nil in this case.
    var totalCandidates: [Decimal] = []
    var date: Date?
    /// True when the date had to be clamped to today because it was missing,
    /// unparseable, or outside the sane window.
    var dateWasClamped: Bool = false
    var merchant: String?
    /// RESO / RIMBORSO / STORNO detected — a refund, not a purchase.
    var isRefund: Bool = false
}

enum ReceiptParser {

    private static let itLocale = Locale(identifier: "it_IT")

    /// Lines whose amount is the real total. Order doesn't matter — each is checked independently.
    private static let totalKeywords = ["TOTALE", "TOT.", "TOTALE COMPLESSIVO", "IMPORTO"]
    /// Lines that *do* contain a currency amount but must never be read as the total — the
    /// CONTANTI trap: cash tendered is reliably larger than what was actually owed.
    private static let decoyKeywords = ["CONTANTI", "CONTANTE", "RESTO", "SUBTOTALE", "SUB TOTALE"]
    private static let refundKeywords = ["RESO", "RIMBORSO", "STORNO"]
    /// Lines that are never the merchant name, even when they're first — boilerplate found at the
    /// top of most Italian receipts, above the actual business name: VAT/tax/phone lines, street
    /// prefixes, and card-network/issuer/transaction-type words that show up on POS payment slips
    /// (which often carry no merchant name at all, only the card processor's own boilerplate).
    private static let merchantNoisePatterns = [
        "P.IVA", "P. IVA", "PARTITA IVA", "C.F.",
        "VIA ", "VIALE ", "CORSO ", "PIAZZA ", "PIAZZETTA ", "TEL.", "TEL ",
        "MASTERCARD", "VISA", "UNICREDIT", "MC CLESS", "ACQUISTO", "POSTEPAY",
        "BANCOMAT", "MAESTRO", "NEXI", "INTESA SANPAOLO", "SELLA", "PAGOBANCOMAT",
        // Toll-free ("numero verde") line — generic POS-slip boilerplate independent of which
        // processor printed it, so this covers issuers beyond the ones named explicitly above.
        "N.VERDE", "NUMERO VERDE",
    ]

    // Year alternative order matters: NSRegularExpression tries alternatives left-to-right, not
    // longest-match, so `\d{4}` must come first or "25-07-2026" would match "20" as the year.
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})"#
    )
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})"#
    )

    static func parse(_ lines: [String], now: Date = .now) -> ReceiptScan {
        var scan = ReceiptScan()

        let totalMatches = amounts(in: lines, matching: totalKeywords, excluding: decoyKeywords)
        let distinctTotals = Set(totalMatches)
        if distinctTotals.count == 1 {
            scan.total = totalMatches.first
        } else if distinctTotals.count > 1 {
            scan.totalCandidates = Array(distinctTotals).sorted()
        }

        scan.isRefund = lines.contains { line in
            refundKeywords.contains { line.uppercased().contains($0) }
        }

        let (date, clamped) = parseDate(in: lines, now: now)
        scan.date = date
        scan.dateWasClamped = clamped

        scan.merchant = merchantName(in: lines)

        return scan
    }

    /// Finds amounts on lines containing any of `keywords`, skipping lines that also (or instead)
    /// match `excluding` — e.g. "TOTALE COMPLESSIVO 90,00" is kept, "CONTANTI 25,00" is dropped even
    /// if a total keyword happened to share a line with it.
    private static func amounts(in lines: [String], matching keywords: [String], excluding: [String]) -> [Decimal] {
        lines.compactMap { line in
            let upper = line.uppercased()
            guard keywords.contains(where: { upper.contains($0) }) else { return nil }
            guard !excluding.contains(where: { upper.contains($0) }) else { return nil }
            return firstAmount(in: line)
        }
    }

    private static func firstAmount(in line: String) -> Decimal? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = amountRegex.firstMatch(in: line, range: range),
              let matchRange = Range(match.range(at: 1), in: line) else { return nil }
        return AmountParser.parse(String(line[matchRange]), locale: itLocale)
    }

    /// Accepts only dates within a sane window (not in the future, not absurdly old); anything else
    /// — missing, unparseable, or out of range — clamps to `now` rather than feeding a bad date into
    /// a form whose Save button silently disables on a future date with no explanation.
    private static func parseDate(in lines: [String], now: Date) -> (Date, Bool) {
        let calendar = Calendar(identifier: .gregorian)
        let earliestSane = calendar.date(byAdding: .year, value: -2, to: now) ?? .distantPast

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = dateRegex.firstMatch(in: line, range: range) else { continue }
            guard let dayRange = Range(match.range(at: 1), in: line),
                  let monthRange = Range(match.range(at: 2), in: line),
                  let yearRange = Range(match.range(at: 3), in: line),
                  let day = Int(line[dayRange]), let month = Int(line[monthRange]),
                  var year = Int(line[yearRange]) else { continue }
            if year < 100 { year += 2000 }

            var components = DateComponents(year: year, month: month, day: day)
            components.calendar = calendar
            guard let candidate = components.date, candidate <= now, candidate >= earliestSane else { continue }
            return (candidate, false)
        }
        return (now, true)
    }

    /// The topmost line that isn't boilerplate (address/VAT/phone) or itself a currency amount —
    /// same tiered idea tinvois-parser uses (known list, else first line), simplified to "first
    /// plausible line" since we don't ship a merchant directory.
    private static func merchantName(in lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let upper = trimmed.uppercased()
            if merchantNoisePatterns.contains(where: { upper.contains($0) }) { continue }
            if firstAmount(in: trimmed) != nil { continue }
            return clean(merchantLine: trimmed)
        }
        return nil
    }

    private static func clean(merchantLine line: String) -> String {
        let trimmed = line.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil else {
            return trimmed
        }
        return trimmed.capitalized
    }
}
