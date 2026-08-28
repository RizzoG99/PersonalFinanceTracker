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
    /// The merchant's street + postal/city line, when the receipt printed both — used only to
    /// narrow a `MerchantCategoryLookup` MapKit search to the right branch/city (never the
    /// device's own location, so no location permission is involved). Never shown to the user.
    var merchantAddress: String?
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
    /// Street-line prefixes — reused to spot the address for `merchantAddress(in:)`, not just to
    /// exclude those lines from the merchant name above.
    private static let streetPrefixes = ["VIA ", "VIALE ", "CORSO ", "PIAZZA ", "PIAZZETTA ", "LUNGOMARE "]
    // Italian postal codes (CAP) are always 5 digits, typically opening the city line, e.g.
    // "73050 SANTA CATERINA".
    private static let postalCodeRegex = try! NSRegularExpression(pattern: #"^\d{5}\b"#)

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

        var totalMatches = amounts(in: lines, matching: totalKeywords, excluding: decoyKeywords)
        // Last resort, confirmed against a real receipt's actual Vision output (2026-08-28,
        // Barrueco S.R.L.): sometimes the whole label column comes back first, then the whole
        // price column, as two separate blocks — not just one line apart, which the lookahead in
        // `amounts(in:)` already covers. Only tried when direct/lookahead matching found nothing.
        if totalMatches.isEmpty {
            totalMatches = amountsByColumnReconstruction(in: lines).compactMap { row in
                let upper = row.label.uppercased()
                guard totalKeywords.contains(where: { upper.contains($0) }) else { return nil }
                guard !decoyKeywords.contains(where: { upper.contains($0) }) else { return nil }
                return row.amount
            }
        }
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
        scan.merchantAddress = merchantAddress(in: lines)

        return scan
    }

    /// Finds amounts on lines containing any of `keywords`, skipping lines that also (or instead)
    /// match `excluding` — e.g. "TOTALE COMPLESSIVO 90,00" is kept, "CONTANTI 25,00" is dropped even
    /// if a total keyword happened to share a line with it.
    ///
    /// A two-column receipt (label left, price right) sometimes comes back from Vision as two
    /// separate lines — "TOTALE COMPLESSIVO" with no digits, then "15,80" on its own right after —
    /// rather than one merged line. When the keyword line itself has no amount, check the next
    /// couple of lines for one that's *just* a bare amount before giving up on that match.
    private static func amounts(in lines: [String], matching keywords: [String], excluding: [String]) -> [Decimal] {
        lines.indices.compactMap { index in
            let line = lines[index]
            let upper = line.uppercased()
            guard keywords.contains(where: { upper.contains($0) }) else { return nil }
            guard !excluding.contains(where: { upper.contains($0) }) else { return nil }
            if let amount = firstAmount(in: line) { return amount }
            for lookahead in lines[(index + 1)...].prefix(2) {
                if let amount = bareAmount(in: lookahead) { return amount }
            }
            return nil
        }
    }

    private static func firstAmount(in line: String) -> Decimal? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = amountRegex.firstMatch(in: line, range: range),
              let matchRange = Range(match.range(at: 1), in: line) else { return nil }
        return AmountParser.parse(String(line[matchRange]), locale: itLocale)
    }

    /// A line that, once trimmed, is nothing but a currency amount (an optional leading "€", and an
    /// optional trailing single-letter VAT class code like "13.00 A" — printed beside itemized
    /// prices on real receipts) — the shape a split price column takes on its own line.
    private static func bareAmount(in line: String) -> Decimal? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "€$"))
            .trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, last.isLetter {
            let withoutSuffix = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            if !withoutSuffix.isEmpty { trimmed = withoutSuffix }
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = amountRegex.firstMatch(in: trimmed, range: range),
              match.range(at: 1) == NSRange(trimmed.startIndex..., in: trimmed) else { return nil }
        return firstAmount(in: trimmed)
    }

    /// Recovers row/price pairs when Vision returns the entire label column, then the entire price
    /// column, as two separate blocks (confirmed on a real receipt, 2026-08-28) — the label lines
    /// right after the "DESCRIZIONE" header (skipping the "PREZZO(€) IVA" column-header noise that
    /// tends to land among them) are zipped, by position, against the contiguous run of bare-amount
    /// lines that follows. Only trustworthy when both sides have the exact same count — anything
    /// else means the assumption doesn't hold for this receipt, so it's dropped rather than guessed.
    private static func amountsByColumnReconstruction(in lines: [String]) -> [(label: String, amount: Decimal)] {
        guard let headerIndex = lines.firstIndex(where: { $0.uppercased().contains("DESCRIZIONE") }) else {
            return []
        }

        var index = lines.index(after: headerIndex)
        var labels: [String] = []
        while index < lines.count, bareAmount(in: lines[index]) == nil {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.uppercased().contains("PREZZO") {
                labels.append(lines[index])
            }
            index += 1
        }

        var amounts: [Decimal] = []
        while index < lines.count, let amount = bareAmount(in: lines[index]) {
            amounts.append(amount)
            index += 1
        }

        guard !labels.isEmpty, labels.count == amounts.count else { return [] }
        return Array(zip(labels, amounts))
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

    /// The street line and postal/city line, joined, when both are present — e.g. "VIA CANTU'. 46,
    /// 73050 SANTA CATERINA". Either alone (or neither) is common too; a street with no city, or a
    /// city with no street, still geocodes reasonably, so this is best-effort, not all-or-nothing.
    private static func merchantAddress(in lines: [String]) -> String? {
        let street = lines.first { line in
            let upper = line.uppercased()
            return streetPrefixes.contains { upper.contains($0) }
        }
        let cityLine = lines.first { line in
            let range = NSRange(line.startIndex..., in: line)
            return postalCodeRegex.firstMatch(in: line, range: range) != nil
        }
        let parts = [street, cityLine].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private static func clean(merchantLine line: String) -> String {
        let trimmed = line.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil else {
            return trimmed
        }
        return trimmed.capitalized
    }
}
