import Testing
@testable import PersonalFinanceTraker
import Foundation

@Suite
struct ReceiptParserTests {

    private static let now = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 27).date!

    // MARK: - Real receipts (transcribed from photos, docs/receipts-test-no-commit/)

    /// PUCE MOTORRAD — motorcycle shop, card payment. All amounts on the receipt agree (935,00), so
    /// there is no CONTANTI-style decoy here; this is the "everything lines up" happy path.
    private static let motorradReceipt = [
        "PUCE MOTORRAD",
        "Di Puce Vittorio & C. s.n.c.",
        "Via G. D'Annunzio n.37D",
        "73038 Spongano (LE)",
        "Part. Iva 04863020758",
        "Tel. 0836 940466",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE          IVA    PREZZO(€)",
        "Vendita               22%    935,00",
        "TOTALE COMPLESSIVO            935,00",
        "DI CUI IVA                    168,61",
        "PAGAMENTO ELETTRONICO          935,00",
        "IMPORTO PAGATO                 935,00",
        "27/05/25 20:02   DOC N 2438-0004",
        "R796AB3003999",
    ]

    /// A bank card POS slip — no itemized business name at all, just card-network boilerplate.
    /// Real test of "merchant genuinely isn't extractable, don't force a bad guess".
    private static let cardSlipReceipt = [
        "UniCredit",
        "Mastercard",
        "MC Cless",
        "ACQUISTO",
        "CORSO PORTA LUCE, 23",
        "GALATINA",
        "Eser. 4466100000057",
        "DATA 24/11/25   ORA 20:28",
        "TML 31150922  SIAN 002987",
        "Mod. Online   CTLS ICC",
        "PAN: ****0368",
        "AUT. H11876 OF   053",
        "Mastercard contactless",
        "IMPORTO €  219,80",
        "COPIA CLIENTE",
        "TRANSAZIONE ESEGUITA",
        "GRAZIE E ARRIVEDERCI",
        "UNICREDIT SPA",
    ]

    /// OTTICA LONGO — optician, 4 line items (23,00 x2, 22,00 x2) summing to the 90,00 total. Real
    /// test that item-line amounts never get mistaken for the total, plus a dash-separated
    /// 4-digit-year date.
    private static let otticaReceipt = [
        "OTTICA LONGO",
        "LONGO S.R.L.",
        "PIAZZETTA INDIPENDENZA 1",
        "73040 ARADEO (LE)",
        "P.I. 03512930755",
        "TEL. 0836/550497",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE                 IVA   Prezzo(€)",
        "Lente a contatto             4%    23,00",
        "#Prodotto con marcatura CE",
        "Lente a contatto             4%    23,00",
        "#Prodotto con marcatura CE",
        "Lente a contatto             4%    22,00",
        "#Prodotto con marcatura CE",
        "Lente a contatto             4%    22,00",
        "#Prodotto con marcatura CE",
        "TOTALE COMPLESSIVO                 90,00",
        "DI CUI IVA                          3,46",
        "Pagamento elettronico               90,00",
        "Importo pagato                      90,00",
        "25-07-2026  11:44",
        "DOCUMENTO N. 1316-0011",
    ]

    /// A second, older OTTICA LONGO visit — the itemized commercial document. Two lens lines
    /// (20,50 x2) summing to 41,00. Date is 12-07-2023, i.e. over 2 years before `now` (2026-08-27):
    /// real evidence for the "old receipt gets clamped, not trusted" policy.
    private static let otticaReceipt2023 = [
        "OTTICA LONGO",
        "LONGO S.R.L.",
        "PIAZZETTA INDIPENDENZA 1",
        "73040 ARADEO (LE)",
        "P.I. 03512930755",
        "TEL. 0386/550497",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE          IVA   Prezzo(€)",
        "Lente a contatto      4%    20,50",
        "#Prodotto con marcatura CE",
        "Lente a contatto      4%    20,50",
        "#Prodotto con marcatura CE",
        "TOTALE COMPLESSIVO           41,00",
        "DI CUI IVA                    1,58",
        "Pagamento elettronico         41,00",
        "Importo pagato                41,00",
        "12-07-2023 19:26",
        "DOCUMENTO N. 0165-0013",
    ]

    /// The companion PagoBancomat authorization slip for the same purchase — a second physical
    /// receipt photographed alongside the first. Unlike the earlier UniCredit card slip, this one
    /// *does* print the actual merchant name ("OTTICA LONGO"), but only after processor boilerplate
    /// ("Sella", the toll-free line, "PAGOBANCOMAT", "ACQUISTO") that must be skipped first.
    private static let sellaCardSlipReceipt = [
        "Sella",
        "N.VERDE 800295571",
        "PAGOBANCOMAT",
        "PAGOBANCOMAT",
        "ACQUISTO",
        "OTTICA LONGO",
        "ARADEO PIAZZA INDIPENDEN",
        "Eser. 593020300001001",
        "DATA 12/07/23  ORA 19:28",
        "TML 02379238  STAN 001881",
        "Mod. online   CTLS ICC",
        "AUT.838546   OPER. C-Less",
        "PagoBancomat",
        "IMPORTO €  41,00",
        "--- COPIA CLIENTE ---",
        "Transazione eseguita",
        "ARRIVEDERCI E GRAZIE",
    ]

    /// SAMANA' — a bar, Porto Cesareo. Slash-separated date with a 4-digit year (previous slash
    /// fixture only covered a 2-digit year).
    private static let samanaReceipt = [
        "SAMANA'",
        "PORTO CESAREO",
        "OPERATORE: amministratore",
        "1 X bar 1.50",
        "1 X bar 2.50",
        "TOTALE EURO 4,00",
        "RITIRARE LO SCONTRINO ALLA CASSA",
        "15/08/2026 17:04",
    ]

    /// CREP MAX — a food stand, cash payment with exact change (no CONTANTI/RESTO decoy since
    /// nothing was owed back). Dash date only 2 days before `now`: a real in-window date that must
    /// NOT be clamped, unlike every dash-date fixture so far which happened to be too old.
    private static let crepMaxReceipt = [
        "CREP MAX",
        "DI PALUMBO MASSIMO",
        "VIA CASA COMUNALE SNC",
        "SANNICOLA 73017 (LE)",
        "P.IVA: 05480640753",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE    IVA   Prezzo(€)",
        "Reparto 1      10%    4,00",
        "TOTALE COMPLESSIVO      4,00",
        "DI CUI IVA               0,36",
        "Pagamento contante        4,00",
        "Importo pagato            4,00",
        "25-08-2026 21:54",
        "DOCUMENTO N. 0653-0008",
    ]

    /// SUPERMERCATO CONAD — the real-world CONTANTI trap this whole feature is designed around,
    /// not a synthetic stand-in: cash tendered (50,50) and change (35,30) both dwarf the actual
    /// total (15,20). Also has real markdown/discount item lines (negative prices) that must never
    /// be read as the total either.
    private static let conadReceipt = [
        "SUPERMERCATO CONAD",
        "GM TRADE SRL - Cassa n. 3",
        "VIA E. MONTI, 4 -73020 CUTROFIA",
        "Tel 0836 541594",
        "PI 05316800753",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE                    IVA    Prezzo(€)",
        "MACINE 350GR MB                VI*      1,85",
        "*TAGLIO PREZZO                 VI*     -0,46",
        "BOMBETTE SPECK E SCAMORZA      VI*      5,31",
        "-M-SCONTO -30%                 VI*     -1,59",
        "TRAMEZZINO SPECK E CIPOLL      VI*      7,08",
        "-M-SCONTO -50%                 VI*     -3,53",
        "ALETTE DI POLLO IN BBQ         VI*      6,64",
        "-M-SCONTO -50%                 VI*     -3,32",
        "TRAMEZZINO MORTADELLA E F      VI*      6,49",
        "-M-SCONTO -50%                 VI*     -3,25",
        "TOTALE COMPLESSIVO                     15,20",
        "DI CUI IVA                              0,00",
        "Pagamento contante                     50,50",
        "Resto                                  35,30",
        "Importo pagato                         15,20",
        "21-08-2026 19:57",
        "DOCUMENTO N. 0688-0346",
    ]

    /// Synthetic — kept alongside the real Conad CONTANTI-trap fixture below as the minimal,
    /// easy-to-read version of the same case: CONTANTI (cash tendered) outranking TOTALE.
    private static let cashPaymentReceipt = [
        "BAR CENTRALE",
        "VIA ROMA 12",
        "SUBTOTALE      23,40",
        "TOTALE EURO    23,40",
        "CONTANTI       25,00",
        "RESTO           1,60",
        "12/03/26",
    ]

    /// CAMILLA-NU BAR — a real two-column thermal receipt where Vision returned the label and its
    /// price as separate lines ("TOTALE COMPLESSIVO" then "15,80" right after) rather than merged
    /// into one. This is the split that let a scan through with no amount at all: the keyword line
    /// itself had no digits on it.
    private static let camillaBarReceipt = [
        "CAMILLA-NU BAR",
        "DIREZIONE 12 SRL",
        "Lungomare C. Colombo - CAPILUNGO",
        "73040 ALLISTE (LE)",
        "Part. IVA 04996160752",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE",
        "PREZZO(€) IVA",
        "PASTO COMPLETO",
        "7,90 B",
        "PASTO COMPLETO",
        "7,90 B",
        "SUBTOTALE",
        "15,80",
        "Tavolo 29",
        "TOTALE COMPLESSIVO",
        "15,80",
        "DI CUI IVA",
        "1,44",
        "PAGAMENTO ELETTRONICO",
        "15,80",
        "IMPORTO PAGATO",
        "15,80",
        "27/08/26 20:34",
    ]

    @Test func extractsTotalWhenAllAmountsAgree() {
        let scan = ReceiptParser.parse(Self.motorradReceipt, now: Self.now)
        #expect(scan.total == 935.00)
        #expect(scan.totalCandidates.isEmpty)
    }

    @Test func extractsMerchantSkippingAddressAndVATLines() {
        let scan = ReceiptParser.parse(Self.motorradReceipt, now: Self.now)
        #expect(scan.merchant == "Puce Motorrad")
    }

    @Test func parsesSlashDateWithTwoDigitYear() {
        let scan = ReceiptParser.parse(Self.motorradReceipt, now: Self.now)
        let expected = DateComponents(calendar: .init(identifier: .gregorian), year: 2025, month: 5, day: 27).date!
        #expect(scan.date == expected)
        #expect(scan.dateWasClamped == false)
    }

    @Test func cardSlipSkipsIssuerAndNetworkNoiseEvenWithNoRealMerchant() {
        let scan = ReceiptParser.parse(Self.cardSlipReceipt, now: Self.now)
        #expect(scan.total == 219.80)
        // This receipt genuinely has no merchant field — it's a POS processor's own slip, not an
        // itemized bill. The parser correctly rejects "UniCredit"/"Mastercard"/"MC Cless"/"ACQUISTO"
        // (issuer and transaction-type boilerplate) and the address line, and falls through to the
        // city name as its best remaining guess. That's an honest limitation, not a bug: there's no
        // merchant directory in scope to know "Galatina" isn't a business name (see the open
        // question in docs/features/2026-08-27-scan-receipt-autofill.md).
        #expect(scan.merchant == "Galatina")
    }

    @Test func ignoresItemLineAmountsAndFindsTheRealTotal() {
        let scan = ReceiptParser.parse(Self.otticaReceipt, now: Self.now)
        #expect(scan.total == 90.00)
        #expect(scan.total != 23.00)
        #expect(scan.total != 22.00)
    }

    @Test func parsesDashDateWithFourDigitYear() {
        let scan = ReceiptParser.parse(Self.otticaReceipt, now: Self.now)
        let expected = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 7, day: 25).date!
        #expect(scan.date == expected)
    }

    @Test func rejectsContantiAsTheTotalWhenPayingCash() {
        let scan = ReceiptParser.parse(Self.cashPaymentReceipt, now: Self.now)
        #expect(scan.total == 23.40)
        #expect(scan.total != 25.00) // CONTANTI (cash tendered)
        #expect(scan.total != 1.60)  // RESTO (change)
    }

    @Test func clampsUnreadableDateToNowAndFlagsIt() {
        let lines = ["SOME SHOP", "TOTALE 10,00"] // no date line at all
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.date == Self.now)
        #expect(scan.dateWasClamped == true)
    }

    @Test func clampsFutureDateRatherThanAcceptingAMisreadDigit() {
        let lines = ["SOME SHOP", "TOTALE 10,00", "27/12/99"] // parses as 2099, in the future
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.date == Self.now)
        #expect(scan.dateWasClamped == true)
    }

    @Test func detectsRefundKeyword() {
        let lines = ["NEGOZIO ROSSI", "RESO", "TOTALE 15,00", "10/01/26"]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.isRefund == true)
    }

    @Test func doesNotFlagRefundOnAnOrdinaryPurchase() {
        let scan = ReceiptParser.parse(Self.otticaReceipt, now: Self.now)
        #expect(scan.isRefund == false)
    }

    @Test func surfacesCandidatesWhenTotalKeywordsDisagree() {
        // Two lines both match a total keyword but with different amounts — a genuinely ambiguous
        // receipt (e.g. a corrected/reprinted total) rather than a clean CONTANTI-style decoy.
        let lines = ["NEGOZIO", "TOTALE 10,00", "TOTALE 12,00"]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.total == nil)
        #expect(scan.totalCandidates.sorted() == [10.00, 12.00])
    }

    @Test func cardSlipCarriesTheRealMerchantNameOnceProcessorBoilerplateIsSkipped() {
        let scan = ReceiptParser.parse(Self.sellaCardSlipReceipt, now: Self.now)
        #expect(scan.total == 41.00)
        #expect(scan.merchant == "Ottica Longo")
    }

    @Test func oldReceiptDateIsClampedRatherThanTrusted() {
        // 12-07-2023 is real and parses fine on its own, but it's over 2 years before `now` —
        // outside the sane window, so the policy is to clamp rather than trust a stale date.
        let scan = ReceiptParser.parse(Self.otticaReceipt2023, now: Self.now)
        #expect(scan.total == 41.00)
        #expect(scan.date == Self.now)
        #expect(scan.dateWasClamped == true)
    }

    @Test func multiPageCaptureOfTwoDocumentsForTheSamePurchaseStaysConsistent() {
        // The itemized receipt and its card-authorization slip, scanned as one multi-page capture
        // (plan's "concatenate all pages' text" rule). Both documents independently say 41,00 —
        // this must NOT be read as two disagreeing totals just because several lines match a total
        // keyword; the dedup-by-value in ReceiptParser.parse should collapse them to one.
        let combined = Self.otticaReceipt2023 + Self.sellaCardSlipReceipt
        let scan = ReceiptParser.parse(combined, now: Self.now)
        #expect(scan.total == 41.00)
        #expect(scan.totalCandidates.isEmpty)
        #expect(scan.merchant == "Ottica Longo")
    }

    @Test func parsesSlashDateWithFourDigitYear() {
        let scan = ReceiptParser.parse(Self.samanaReceipt, now: Self.now)
        let expected = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 15).date!
        #expect(scan.date == expected)
        #expect(scan.dateWasClamped == false)
    }

    @Test func extractsTotalAndMerchantFromABarReceipt() {
        let scan = ReceiptParser.parse(Self.samanaReceipt, now: Self.now)
        #expect(scan.total == 4.00)
        // clean(merchantLine:) trims trailing punctuation, so the apostrophe in "SAMANA'" goes too.
        #expect(scan.merchant == "Samana")
    }

    @Test func recentDashDateIsTrustedNotClamped() {
        // Every earlier dash-date fixture happened to be over 2 years old (correctly clamped).
        // This one is 2 days before `now` — the positive case that must NOT be clamped.
        let scan = ReceiptParser.parse(Self.crepMaxReceipt, now: Self.now)
        let expected = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 25).date!
        #expect(scan.date == expected)
        #expect(scan.dateWasClamped == false)
        #expect(scan.total == 4.00)
    }

    @Test func realConadReceiptRejectsCashTenderedAndChangeAsTheTotal() {
        // The actual case this feature's design revolves around, on a real receipt: cash tendered
        // (50,50) and change (35,30) both dwarf the real total (15,20). Also exercises real
        // markdown/discount lines with negative prices, which must never be read as the total.
        let scan = ReceiptParser.parse(Self.conadReceipt, now: Self.now)
        #expect(scan.total == 15.20)
        #expect(scan.total != 50.50)
        #expect(scan.total != 35.30)
        #expect(scan.totalCandidates.isEmpty)
    }

    @Test func realConadReceiptExtractsMerchantAndRecentDate() {
        let scan = ReceiptParser.parse(Self.conadReceipt, now: Self.now)
        #expect(scan.merchant == "Supermercato Conad")
        let expected = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 21).date!
        #expect(scan.date == expected)
        #expect(scan.dateWasClamped == false)
    }

    @Test func realBarReceiptFindsTheTotalWhenLabelAndPriceAreSplitAcrossLines() {
        let scan = ReceiptParser.parse(Self.camillaBarReceipt, now: Self.now)
        #expect(scan.total == 15.80)
        #expect(scan.totalCandidates.isEmpty)
        #expect(scan.merchant == "Camilla-Nu Bar")
    }

    @Test func returnsNoTotalWhenNothingMatchesAKeyword() {
        let lines = ["NEGOZIO", "articolo 5,00"]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.total == nil)
        #expect(scan.totalCandidates.isEmpty)
    }
}
