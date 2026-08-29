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

/// One label→amount pair, as produced by Vision's own table analysis
/// (`RecognizeDocumentsRequest`). Trusted over any column heuristic the parser can apply to flat
/// lines, since it comes from layout analysis of the actual page geometry.
struct ReceiptRow: Equatable {
    var label: String
    var amount: Decimal
}

/// What one scan hands to `ReceiptParser`: the flat recognized lines plus, when Vision detected a
/// table, its rows. `rows` is empty for receipts Vision saw no table in — every heuristic below
/// still works off `lines` alone, so an empty `rows` costs accuracy but nothing else.
struct ReceiptDocument: Equatable {
    var lines: [String] = []
    var rows: [ReceiptRow] = []
    /// Money amounts Vision's data detector read, keyed by index into `lines`. These come back as a
    /// `Decimal` the detector parsed itself, so they cover shapes our own regex doesn't — a missing
    /// thousands separator, a currency symbol glued to the digits, a decimal comma OCR'd as a dot.
    /// One per line (the rightmost, which is the price column on a receipt).
    var detectedAmounts: [Int: Decimal] = [:]
    /// Dates the data detector read anywhere on the page, in page order. Used only to rescue a
    /// receipt whose printed date our own regex couldn't find — see `parseDate`.
    var detectedDates: [Date] = []
    /// Each line's bounding-box height, normalized to the page, keyed by index into `lines`. The
    /// store name is the largest text on a receipt, which is what `merchantName` uses it for.
    /// `Double` rather than `CGFloat` to keep this file free of CoreGraphics.
    var lineHeights: [Int: Double] = [:]
    /// Mean of Vision's per-line recognition confidence, 0…1. Not used for parsing — it exists so
    /// two OCR passes over the *same* photo can be compared, which is how the low-light retry in
    /// `ReceiptTextRecognizer` decides whether boosting contrast actually helped.
    var meanConfidence: Double = 0
}

enum ReceiptParser {

    /// Uppercased *and* stripped of diacritics, which is the form every keyword list here is
    /// written in. Vision decorates letters it is unsure of — the Cremeria receipt came back with
    /// "TỌT. COMPLESSIVO" (U+1ECC), which matched neither "TOT." nor "TOTALE", so the total block's
    /// own heading was not recognized as structure and became the merchant name.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: enLocale).uppercased()
    }

    private static let itLocale = Locale(identifier: "it_IT")
    private static let enLocale = Locale(identifier: "en_US")

    /// Lines whose amount is the real total, in **authority order** — the first tier that matches
    /// anything decides, and the tiers below it are never consulted.
    ///
    /// This mirrors the Italian "documento commerciale" standard rather than polling every keyword
    /// as an equal: a compliant receipt prints `TOTALE COMPLESSIVO` (the amount owed) and
    /// `IMPORTO PAGATO` (the same amount, corroborating) in a fixed block, so treating them as
    /// peers and demanding they agree gave OCR two independent chances to corrupt one value and
    /// turn a perfectly readable receipt into an ambiguous one. The mandated wording wins outright;
    /// the loose tier exists only for slips that don't follow the standard (old registers, bank POS
    /// receipts printing a bare `IMPORTO €`).
    /// English tiers sit *below* both mandated Italian wordings and above the loose tier, for the
    /// same reason the Italian ones are ordered: "GRAND TOTAL"/"BALANCE DUE" name the amount owed
    /// outright, while a bare "TOTAL" also appears inside "SUB TOTAL" and "TOTAL TAX" and so has to
    /// be the last thing consulted. Counts below are from the 195-receipt corpus in
    /// `ReceiptForeignCorpusTests`, which is what these tiers were derived from rather than guessed.
    private static let rankedTotalKeywords: [[String]] = [
        ["TOTALE COMPLESSIVO"],
        ["IMPORTO PAGATO"],
        // GRAND TOTAL x5, TOTAL DUE x9, BALANCE DUE x22, AMOUNT DUE x11.
        ["GRAND TOTAL", "TOTAL DUE", "BALANCE DUE", "AMOUNT DUE"],
        // Bare TOTAL x125 — the common case, but only once the qualified wordings above have had
        // their chance and the decoys below have removed SUB TOTAL x46 and TOTAL TAX x9.
        ["TOTALE", "TOT.", "IMPORTO", "TOTAL"],
    ]
    /// Lines that *do* contain a currency amount but must never be read as the total — the
    /// CONTANTI trap: cash tendered is reliably larger than what was actually owed.
    /// The English half mirrors the Italian one exactly: SUB TOTAL / TOTAL TAX are totals of the
    /// wrong thing, and CASH / CHANGE / TENDER / TIP / GRATUITY are the CONTANTI trap in English —
    /// cash tendered and suggested tips both print larger than what was actually owed.
    private static let decoyKeywords = [
        "CONTANTI", "CONTANTE", "RESTO", "SUBTOTALE", "SUB TOTALE",
        "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "TOTAL TAX", "TAX TOTAL", "NET TOTAL",
        "CASH", "CHANGE", "TENDER", "TIP", "GRATUITY",
    ]
    /// RESO / RIMBORSO / STORNO as whole words — the standard prints them in the header
    /// ("DOCUMENTO COMMERCIALE di reso"). Word-bounded because a bare substring test flags any
    /// merchant or product that merely contains the letters, e.g. "RESORT", "PRESOTTO".
    private static let refundRegex = try! NSRegularExpression(pattern: #"\b(RESO|RIMBORSO|STORNO)\b"#)
    /// Lines that are never the merchant name, even when they're first — boilerplate found at the
    /// top of most Italian receipts, above the actual business name: VAT/tax/phone lines, street
    /// prefixes, and card-network/issuer/transaction-type words that show up on POS payment slips
    /// (which often carry no merchant name at all, only the card processor's own boilerplate).
    private static let merchantNoisePatterns = [
        // "PART. IVA" is the spelling two of the six real fixtures use; without it the VAT line
        // won the merchant vote outright ("Part. IVA 04996160752", 2026-08-29).
        "P.IVA", "P. IVA", "PART. IVA", "PART.IVA", "PARTITA IVA", "C.F.",
        "VIA ", "VIALE ", "CORSO ", "PIAZZA ", "PIAZZETTA ", "TEL.", "TEL ",
        "MASTERCARD", "VISA", "UNICREDIT", "MC CLESS", "ACQUISTO", "POSTEPAY",
        "BANCOMAT", "MAESTRO", "NEXI", "INTESA SANPAOLO", "SELLA", "PAGOBANCOMAT",
        // Toll-free ("numero verde") line — generic POS-slip boilerplate independent of which
        // processor printed it, so this covers issuers beyond the ones named explicitly above.
        "N.VERDE", "NUMERO VERDE",
    ]
    /// Words that mark a line as part of the receipt's *structure* rather than its content — the
    /// total block, the item-table headers, the "documento commerciale" preamble. A shop is never
    /// named any of these, so they can never be the merchant no matter how large they print.
    ///
    /// This exists because the size heuristic in `merchantName` is only as good as the pool it
    /// chooses from, and on real receipts the total line is legitimately the biggest text on the
    /// page — it returned "Totale Cohplessivo" (Vision's own misreading of TOTALE COMPLESSIVO) and
    /// "INA Prezzo(€" as shop names on two of the six fixtures, 2026-08-29. Built from the keyword
    /// lists above rather than retyped, so a keyword added for total-detection is excluded here too.
    private static let structuralKeywords: [String] =
        rankedTotalKeywords.flatMap { $0 } + decoyKeywords + [
            // "DOCUMENTO" alone, not the full "DOCUMENTO COMMERCIALE": Vision read that phrase as
            // "DOCUMENTO COMMERTLALE" on one fixture and "Totale Cohplessivo" on another, so
            // matching the whole thing is matching what OCR is most likely to have broken. The
            // first word survives; no shop is called "Documento".
            // "DESCRIZI", not "DESCRIZIONE": Vision returned "DESCRIZIOHE" on Puce Motorrad, and an
            // unmatched column header then beat the shop name in the size vote. Same reasoning as
            // "DOCUMENTO" above — match the stem OCR gets right, not the ending it garbles.
            "DESCRIZ", "PREZZO", "DOCUMENTO", "VENDITA O PRESTAZIONE",
            "NUMERO PEZZI", "PAGAMENTO", "PAGAMENTI", "CUI IVA",
        ]

    /// Street-line prefixes — reused to spot the address for `merchantAddress(in:)`, not just to
    /// exclude those lines from the merchant name above.
    private static let streetPrefixes = ["VIA ", "VIALE ", "CORSO ", "PIAZZA ", "PIAZZETTA ", "LUNGOMARE "]
    // Italian postal codes (CAP) are always 5 digits, typically opening the city line, e.g.
    // "73050 SANTA CATERINA".
    // A single leading non-digit is tolerated because OCR routinely invents one: "(3040 ALLISTE (LE)"
    // is really "73040 ALLISTE (LE)" (Camilla-Nu Bar, 2026-08-29), and left unmatched that city line
    // was the tallest surviving merchant candidate on the receipt.
    private static let postalCodeRegex = try! NSRegularExpression(pattern: #"^\D?\d{4,5}\b"#)
    /// A line that is mostly digits is a register serial, a document number, or a table number —
    /// never a shop name. "R7964B3003999" won the merchant vote on Puce Motorrad before this.
    private static func isDigitHeavy(_ line: String) -> Bool {
        let digits = line.filter(\.isNumber).count
        let letters = line.filter(\.isLetter).count
        return digits > letters
    }

    // Year alternative order matters: NSRegularExpression tries alternatives left-to-right, not
    // longest-match, so `\d{4}` must come first or "25-07-2026" would match "20" as the year.
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})"#
    )
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})"#
    )

    /// Convenience for callers (and the fixture tests) that only have flat recognized lines.
    static func parse(_ lines: [String], now: Date = .now) -> ReceiptScan {
        parse(ReceiptDocument(lines: lines), now: now)
    }

    static func parse(_ document: ReceiptDocument, now: Date = .now) -> ReceiptScan {
        let lines = document.lines
        var scan = ReceiptScan()

        // Most authoritative keyword tier that matches anything wins outright; within a tier, the
        // three ways of pairing a keyword with an amount are tried cheapest-first.
        var totalMatches: [Decimal] = []
        for keywords in rankedTotalKeywords {
            // Vision's own table rows, when it found a table — label and price already paired by
            // layout analysis, so no column-order guessing is involved.
            totalMatches = totals(in: document.rows, matching: keywords)
            // Keyword and amount on the same recognized line (or one right below it).
            if totalMatches.isEmpty {
                totalMatches = amounts(
                    in: lines,
                    matching: keywords,
                    excluding: decoyKeywords,
                    detectedAmounts: document.detectedAmounts
                )
            }
            // Last resort, confirmed against a real receipt's actual Vision output (2026-08-28,
            // Barrueco S.R.L.): sometimes the whole label column comes back first, then the whole
            // price column, as two separate blocks — not just one line apart, which the lookahead
            // in `amounts(in:)` already covers.
            if totalMatches.isEmpty {
                totalMatches = totals(in: amountsByColumnReconstruction(in: lines), matching: keywords)
            }
            if !totalMatches.isEmpty { break }
        }
        // Nothing keyword-driven matched. On a split-column receipt that usually means OCR damaged
        // the very words the tiers look for — "TOTALE COHPLESSIVO", "FREZZO(E) IVA" (both real,
        // Barrueco 2026-08-29) — so the fallback deliberately reads none of them.
        if totalMatches.isEmpty, let modal = modalAmountInPriceColumn(in: lines) {
            totalMatches = [modal]
        }
        let distinctTotals = Set(totalMatches)
        if distinctTotals.count == 1 {
            scan.total = totalMatches.first
        } else if distinctTotals.count > 1 {
            scan.totalCandidates = Array(distinctTotals).sorted()
        }

        scan.isRefund = lines.contains { line in
            let upper = normalized(line)
            return refundRegex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)) != nil
        }

        let (date, clamped) = parseDate(
            in: lines, detected: document.detectedDates, now: now, monthFirst: prefersMonthFirst(in: lines)
        )
        scan.date = date
        scan.dateWasClamped = clamped

        scan.merchant = merchantName(in: lines, heights: document.lineHeights)
        scan.merchantAddress = merchantAddress(in: lines)

        return scan
    }

    /// The amounts of whichever rows are tagged with a total keyword and not a decoy one. Shared by
    /// the Vision-table tier and the flat-line column-reconstruction fallback, which both produce
    /// the same label/amount shape.
    private static func totals(in rows: [ReceiptRow], matching keywords: [String]) -> [Decimal] {
        rows.compactMap { row in
            let upper = normalized(row.label)
            guard keywords.contains(where: { upper.contains($0) }) else { return nil }
            guard !decoyKeywords.contains(where: { upper.contains($0) }) else { return nil }
            return row.amount
        }
    }

    /// Finds amounts on lines containing any of `keywords`, skipping lines that also (or instead)
    /// match `excluding` — e.g. "TOTALE COMPLESSIVO 90,00" is kept, "CONTANTI 25,00" is dropped even
    /// if a total keyword happened to share a line with it.
    ///
    /// A two-column receipt (label left, price right) sometimes comes back from Vision as two
    /// separate lines — "TOTALE COMPLESSIVO" with no digits, then "15,80" on its own right after —
    /// rather than one merged line. When the keyword line itself has no amount, check the next
    /// couple of lines for one that's *just* a bare amount before giving up on that match.
    private static func amounts(
        in lines: [String],
        matching keywords: [String],
        excluding: [String],
        detectedAmounts: [Int: Decimal] = [:]
    ) -> [Decimal] {
        lines.indices.compactMap { index in
            let line = lines[index]
            let upper = normalized(line)
            guard keywords.contains(where: { upper.contains($0) }) else { return nil }
            guard !excluding.contains(where: { upper.contains($0) }) else { return nil }
            if let amount = firstAmount(in: line) { return amount }
            // Our regex needs the exact `d,dd` shape; the data detector doesn't, so it rescues
            // keyword lines whose amount is printed in a form the regex can't read.
            if let detected = detectedAmounts[index] { return detected }
            for lookahead in lines.indices.dropFirst(index + 1).prefix(2) {
                if let amount = bareAmount(in: lines[lookahead]) {
                    // Only when this is a lone amount sitting under its label. If the very next
                    // line is *also* a bare amount we are not looking at a label/price pair at all
                    // — we have run off the end of the label column into the price column, where
                    // the first entry is the first item's price, not this label's. That is exactly
                    // how "IMPORTO PAGATO" came back as 7,90 on a 15,80 receipt (Camilla-Nu Bar,
                    // 2026-08-29): confidently wrong, with no candidates to warn anyone.
                    // ...unless the run of amounts all carries the *same* value, which is a total
                    // printed more than once, not a column of different item prices. The Cremeria
                    // receipt prints "TOT. COMPLESSIVO" above "5,00 / 5,00" and the stricter rule
                    // rejected it outright, reporting no total at all (device log, 2026-08-29).
                    // Ambiguity only exists when the amounts disagree.
                    var next = lines.index(after: lookahead)
                    while next < lines.count, let following = bareAmount(in: lines[next]) {
                        guard following == amount else { return nil }
                        next = lines.index(after: next)
                    }
                    return amount
                }
                if let detected = detectedAmounts[lookahead] { return detected }
            }
            return nil
        }
    }

    /// Reads an amount whose separator convention is decided by the text itself, not by a locale.
    ///
    /// "1.234,56" and "1,234.56" are the same money written two ways, and which is which is settled
    /// by whichever separator comes *last* — that one is always the decimal point. Locale cannot
    /// settle it: the device locale describes the user, while the receipt was printed wherever it
    /// was printed. Amounts with a single separator are left to `AmountParser`, which already
    /// resolves "13.00" under it_IT correctly.
    private static func parseAmount(_ text: String) -> Decimal? {
        guard let lastComma = text.lastIndex(of: ","), let lastDot = text.lastIndex(of: ".") else {
            return AmountParser.parse(text, locale: itLocale)
        }
        let decimalIsComma = lastComma > lastDot
        return AmountParser.parse(text, locale: decimalIsComma ? itLocale : enLocale)
    }

    private static func firstAmount(in line: String) -> Decimal? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = amountRegex.firstMatch(in: line, range: range),
              let matchRange = Range(match.range(at: 1), in: line) else { return nil }
        return parseAmount(String(line[matchRange]))
    }

    /// A line that, once trimmed, is nothing but a currency amount (an optional leading "€", an
    /// optional leading "-" for a discount row — confirmed real Vision output, 2026-08-28,
    /// "L'Autentica" receipt: "- 1.28" with the space Vision inserts after the dash — and an
    /// optional trailing single-character VAT class code like "13.00 A", sometimes misrecognized
    /// as punctuation instead of a letter (confirmed real Vision output, 2026-08-28, second
    /// "L'Autentica" scan: "1.50!") — printed beside itemized prices on real receipts) — the shape
    /// a split price column takes on its own line.
    /// Internal, not private: `ReceiptTextRecognizer` uses it to tell a Vision table's price cell
    /// from its label cells, so both sides agree on what "is an amount" means.
    static func bareAmount(in line: String) -> Decimal? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "€$"))
            .trimmingCharacters(in: .whitespaces)
        var isNegative = false
        if trimmed.hasPrefix("-") {
            isNegative = true
            trimmed = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        if let last = trimmed.last, !last.isNumber {
            let withoutSuffix = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            if !withoutSuffix.isEmpty { trimmed = withoutSuffix }
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = amountRegex.firstMatch(in: trimmed, range: range),
              match.range(at: 1) == NSRange(trimmed.startIndex..., in: trimmed),
              let amount = firstAmount(in: trimmed) else { return nil }
        return isNegative ? -amount : amount
    }

    /// The amount printed most often in the receipt's price column, when that column came back as
    /// its own run of bare-amount lines.
    ///
    /// This leans on the "documento commerciale" standard rather than on any wording: a compliant
    /// receipt prints the same total four or five times over — SUBTOTALE, TOTALE COMPLESSIVO,
    /// IMPORTO PAGATO, and the VAT-class line all carry it — while every item price, the VAT
    /// amount, and any discount appear once each. So in a run of prices the mode *is* the total,
    /// and it needs no label pairing, no keyword, and no column-order guessing, which is what makes
    /// it survive the OCR corruption that defeats the tiers above.
    ///
    /// Deliberately conservative: it wants a real run (a stray pair of prices is not a column), and
    /// a mode that is actually repeated and actually unique. A tie returns nil rather than picking
    /// one, so the caller falls through to "no total" and asks the user instead of guessing.
    ///
    /// ponytail: mode over the longest run only. A receipt printing its total once and the same
    /// item price twice would beat it — no fixture does, and the failure is a visible wrong number
    /// rather than a silent one. Pair labels properly if that ever shows up.
    private static func modalAmountInPriceColumn(in lines: [String]) -> Decimal? {
        var longestRun: [Decimal] = []
        var currentRun: [Decimal] = []
        for line in lines {
            if let amount = bareAmount(in: line) {
                currentRun.append(amount)
            } else {
                if currentRun.count > longestRun.count { longestRun = currentRun }
                currentRun = []
            }
        }
        if currentRun.count > longestRun.count { longestRun = currentRun }
        guard longestRun.count >= 3 else { return nil }

        let counts = longestRun.reduce(into: [Decimal: Int]()) { $0[$1, default: 0] += 1 }
        guard let best = counts.max(by: { $0.value < $1.value }), best.value > 1,
              counts.filter({ $0.value == best.value }).count == 1 else { return nil }
        return best.key
    }

    /// Recovers row/price pairs when Vision returns the entire label column and the entire price
    /// column as two separate blocks (confirmed on real receipts, 2026-08-28) rather than merged
    /// per-row. Only trustworthy when both sides have the exact same count — anything else means
    /// the assumption doesn't hold for this receipt, so it's dropped rather than guessed.
    private static func amountsByColumnReconstruction(in lines: [String]) -> [ReceiptRow] {
        guard let headerIndex = lines.firstIndex(where: { normalized($0).contains("DESCRIZ") }) else {
            return []
        }

        // Fixed boilerplate on every Italian "documento commerciale" receipt (also seen, in this
        // exact wording, on every other fixture in this file) — usually prints before DESCRIZIONE,
        // but confirmed real Vision output (2026-08-28, "L'Autentica") can place it after, right in
        // the label run.
        let nonItemLabelKeywords = ["PREZZO", "DOCUMENTO COMMERCIALE", "PRESTAZIONE"]

        // "NUMERO PEZZI" (item count) hard-stops the label block rather than just being excluded
        // from it: it's a count, not a price, so it has no matching row in the amount column, and
        // on the reversed layout below there's no trailing amount line to naturally end the loop —
        // everything after it is register/footer metadata (VAT breakdown, date, doc number).
        var labels: [String] = []
        var labelIndex = lines.index(after: headerIndex)
        while labelIndex < lines.count, bareAmount(in: lines[labelIndex]) == nil {
            let trimmed = lines[labelIndex].trimmingCharacters(in: .whitespaces)
            let upper = normalized(trimmed)
            if upper.contains("NUMERO PEZZI") { break }
            if !trimmed.isEmpty, !nonItemLabelKeywords.contains(where: { upper.contains($0) }) {
                labels.append(lines[labelIndex])
            }
            labelIndex += 1
        }
        guard !labels.isEmpty else { return [] }

        // Order A (Barrueco, 2026-08-27): the price column prints right after the label block,
        // once any remaining boilerplate between them (skipped above, but not stopped on) is
        // walked past.
        var forwardIndex = lines.index(after: headerIndex)
        while forwardIndex < lines.count, bareAmount(in: lines[forwardIndex]) == nil { forwardIndex += 1 }
        var forwardAmounts: [Decimal] = []
        while forwardIndex < lines.count, let amount = bareAmount(in: lines[forwardIndex]) {
            forwardAmounts.append(amount)
            forwardIndex += 1
        }
        if forwardAmounts.count == labels.count {
            return zip(labels, forwardAmounts).map(ReceiptRow.init)
        }

        // Order B (L'Autentica, 2026-08-28 second scan): the price column prints *before* the
        // header instead, bounded above by the "PREZZO(€) IVA" column header. A stray non-amount
        // line in between (the "NUMERO PEZZI" item-count value) is skipped rather than treated as
        // a boundary, since it has no counterpart on the label side either.
        var backwardAmounts: [Decimal] = []
        var backwardIndex = headerIndex - 1
        while backwardIndex >= 0, !normalized(lines[backwardIndex]).contains("PREZZO") {
            if let amount = bareAmount(in: lines[backwardIndex]) {
                backwardAmounts.append(amount)
            }
            backwardIndex -= 1
        }
        backwardAmounts.reverse()
        guard backwardAmounts.count == labels.count else { return [] }
        return zip(labels, backwardAmounts).map(ReceiptRow.init)
    }

    /// Whether this receipt writes dates month-first. Decided by the receipt's own wording rather
    /// than by the device locale, which says where the *user* is, not where the receipt was printed
    /// — a traveller scanning a US check on an Italian phone needs the US reading.
    ///
    /// Italian markers win over English ones, because an Italian receipt can legitimately contain
    /// the substring "TOTAL" (inside "TOTALE") while the reverse does not happen.
    private static func prefersMonthFirst(in lines: [String]) -> Bool {
        var sawEnglish = false
        for line in lines {
            let upper = normalized(line)
            if italianMarkers.contains(where: { upper.contains($0) }) { return false }
            if !sawEnglish, englishMarkers.contains(where: { upper.contains($0) }) { sawEnglish = true }
        }
        return sawEnglish
    }

    private static let italianMarkers = ["TOTALE", "IMPORTO", "SCONTRINO", "DOCUMENTO", "PREZZO", "IVA"]
    private static let englishMarkers = ["TOTAL", "SUBTOTAL", "SUB TOTAL", "THANK YOU", "SERVER", "CASHIER", "AMOUNT DUE"]

    /// Accepts only dates within a sane window (not in the future, not absurdly old); anything else
    /// — missing, unparseable, or out of range — clamps to `now` rather than feeding a bad date into
    /// a form whose Save button silently disables on a future date with no explanation.
    ///
    /// `detected` is the data detector's own reading of the page. It's tried only *after* the regex
    /// gives up, never before: a bare time like "19:25" also comes back as a detected date (today,
    /// at that time), which would otherwise outrank the real printed date. As a last chance before
    /// clamping, though, it's free accuracy.
    private static func parseDate(
        in lines: [String], detected: [Date], now: Date, monthFirst: Bool
    ) -> (Date, Bool) {
        let calendar = Calendar(identifier: .gregorian)
        let earliestSane = calendar.date(byAdding: .year, value: -2, to: now) ?? .distantPast

        func validate(day: Int, month: Int, year: Int) -> Date? {
            var components = DateComponents(year: year, month: month, day: day)
            components.calendar = calendar
            guard let candidate = components.date, candidate <= now, candidate >= earliestSane else {
                return nil
            }
            return candidate
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = dateRegex.firstMatch(in: line, range: range) else { continue }
            guard let firstRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line),
                  let yearRange = Range(match.range(at: 3), in: line),
                  let first = Int(line[firstRange]), let second = Int(line[secondRange]),
                  var year = Int(line[yearRange]) else { continue }
            if year < 100 { year += 2000 }

            // `05/06/2026` is 5 June in Italy and 6 May in the US, and nothing in the digits says
            // which. The receipt's own wording does, so the caller decides the order — and this is
            // the one place a foreign receipt could otherwise produce a *silently* wrong value
            // rather than a visibly missing one. Either reading is tried second when the preferred
            // one is impossible, which is what rescues an unambiguous "24/11/25" on an English
            // receipt and "5/26/2016" on an Italian-defaulted one alike.
            let preferred = monthFirst
                ? validate(day: second, month: first, year: year)
                : validate(day: first, month: second, year: year)
            let fallbackOrder = monthFirst
                ? validate(day: first, month: second, year: year)
                : validate(day: second, month: first, year: year)
            guard let candidate = preferred ?? fallbackOrder else { continue }
            return (candidate, false)
        }
        if let fallback = detected.first(where: { $0 <= now && $0 >= earliestSane }) {
            return (calendar.startOfDay(for: fallback), false)
        }
        return (now, true)
    }

    /// The merchant's own name, picked from the lines that aren't boilerplate (address/VAT/phone/
    /// card-network) or themselves a currency amount.
    ///
    /// Among those candidates, the **largest** one wins when Vision gave us line heights: a store
    /// prints its name bigger than anything else on the receipt, so typography settles it without
    /// anyone having to add the offending line to `merchantNoisePatterns` first. That list still
    /// filters, because it encodes something height can't — a POS slip whose biggest text really is
    /// "MASTERCARD" has no merchant name on it at all. Falling back to the topmost candidate keeps
    /// the old behaviour for callers with no geometry (every fixture test).
    private static func merchantName(in lines: [String], heights: [Int: Double]) -> String? {
        // The merchant block is whatever prints *above* the item table, so the item-table header is
        // a far better bound than a fixed line count. Falls back to the old 15-line cap when the
        // header is missing or is itself line 0 (Vision sometimes emits the table first).
        let headerIndex = lines.firstIndex { normalized($0).contains("DESCRIZ") } ?? 0
        let searchLimit = headerIndex > 0 ? headerIndex : min(15, lines.count)

        let candidates = lines.indices.prefix(searchLimit).filter { index in
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let upper = normalized(trimmed)
            if merchantNoisePatterns.contains(where: { upper.contains($0) }) { return false }
            if structuralKeywords.contains(where: { upper.contains($0) }) { return false }
            // The address is already recognized for `merchantAddress(in:)`; reuse those same two
            // detectors here rather than keeping a second, drifting copy of the street list — the
            // street line "Lungomare C. Colombo" was in `streetPrefixes` but not in
            // `merchantNoisePatterns`, so it was excluded from the address and won the name.
            if streetPrefixes.contains(where: { upper.contains($0) }) { return false }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if postalCodeRegex.firstMatch(in: trimmed, range: range) != nil { return false }
            if isDigitHeavy(trimmed) { return false }
            return firstAmount(in: trimmed) == nil
        }

        guard let topmost = candidates.first else { return nil }
        // Strictly-greater, so ties keep the earlier (higher on the page) line.
        let best = candidates.reduce(topmost) { best, index in
            (heights[index] ?? 0) > (heights[best] ?? 0) ? index : best
        }
        return clean(merchantLine: lines[best].trimmingCharacters(in: .whitespaces))
    }

    /// The street line and postal/city line, joined, when both are present — e.g. "VIA CANTU'. 46,
    /// 73050 SANTA CATERINA". Either alone (or neither) is common too; a street with no city, or a
    /// city with no street, still geocodes reasonably, so this is best-effort, not all-or-nothing.
    private static func merchantAddress(in lines: [String]) -> String? {
        let street = lines.first { line in
            let upper = normalized(line)
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
