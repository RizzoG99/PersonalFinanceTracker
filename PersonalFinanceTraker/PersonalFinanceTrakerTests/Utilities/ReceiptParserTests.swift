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

    /// BARRUECO S.R.L. — the *actual* Vision console output captured off a real device (2026-08-28),
    /// not a hand-transcribed guess (an earlier guess at this same receipt's text happened to already
    /// pass, which taught nothing about the real miss). Vision returned the whole label column first,
    /// then the whole price column, six lines apart — worse than the 1-2-line split
    /// `camillaBarReceipt` covers, and the reason `amountsByColumnReconstruction` exists. Amounts also
    /// use "." as the decimal mark here (an OCR/font read, not "," as printed) — already handled by
    /// `AmountParser`'s existing single-alternate-separator normalization, not something added for
    /// this fixture.
    private static let barruecoReceipt = [
        "BARRUECO S.R.L.",
        "VIA CANTU'. 46",
        "73050 SANTA CATERINA",
        "NARDO•",
        "LE:",
        "P. IVA 0338706//53",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "DESCRIZIONE",
        "P.F. ICONICA",
        "SUBTOTALE",
        "TOTALE COMPLESSIVO",
        "DI CUI IVA",
        "PAGAMENTO ELETTRONICO",
        "IMPORTO PAGATO",
        "PREZZO(€) IVA",
        "13.00 A",
        "13.00",
        "13.00",
        "1.18",
        "13.00",
        "13.00",
        "A: IVA 10.00%",
        "25/08/26 19:25",
        "DOC. 0983-0009",
        "RT",
        "96MKR005958",
        "RIF N.9",
        "ASPORTO",
        "42",
    ]

    @Test func columnSplitBarruecoReceiptFindsTheTotal() {
        let scan = ReceiptParser.parse(Self.barruecoReceipt, now: Self.now)
        #expect(scan.total == 13.00)
        #expect(scan.totalCandidates.isEmpty)
        #expect(scan.merchant == "Barrueco S.R.L")
    }

    @Test func columnSplitBarruecoReceiptExtractsAnAddressForCategoryLookup() {
        // Feeds MerchantCategoryLookup's MapKit search — never the device's own location.
        let scan = ReceiptParser.parse(Self.barruecoReceipt, now: Self.now)
        #expect(scan.merchantAddress == "VIA CANTU'. 46, 73050 SANTA CATERINA")
    }

    @Test func columnSplitBarruecoReceiptFindsTheRecentDate() {
        let scan = ReceiptParser.parse(Self.barruecoReceipt, now: Self.now)
        let expected = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 25).date!
        #expect(scan.date == expected)
        #expect(scan.dateWasClamped == false)
    }

    // Real Vision output (2026-08-28) — column-split like Barrueco, but with two extra wrinkles
    // that receipt didn't have: the boilerplate "DOCUMENTO COMMERCIALE"/"di vendita o prestazione"
    // lines land AFTER the label column instead of before it, and a discount row ("- 1.28", with
    // the space Vision inserts after the dash) and an item-count row ("NUMERO PEZZI" / "2", a
    // count rather than a price) both sit in the mix.
    private static let lAutenticaReceipt = [
        "L'AUTENTICA",
        "di MICHALI GIOVANNI",
        "Via P. Togliatti. 29 - Tel. 0836/315585",
        "73040 ARADEO (LE)",
        "C.F.: HGHCNN74E30A350X",
        "P. IVA 04951370750",
        "DESCRIZIONE",
        "REP. SALUMERIA",
        "VIRTUAL",
        "SUBTOTALE",
        "SCONTO 15 DIPENDENTI",
        "SUBTOTALE",
        "TOTALE COMPLESSIVO",
        "DI CUI IVA",
        "PAGAMENTO CONTANTE",
        "IMPORTO PAGATO",
        "NUMERO PEZZI",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "PREZZO(E) IVA",
        "7.00 L",
        "1.50 L",
        "8,50",
        "- 1.28",
        "7.22",
        "7.22",
        "0,00",
        "7,22",
        "7.22",
        "2",
        "L: *V! Ventilazione IVA",
        "NUMERO PEZZI",
        "CASSA #1",
        "28/08/26 13:27",
        "RT",
        "2",
        "CASSA",
        "96IP3000885",
        "DOC. 0554-0067",
    ]

    @Test func columnSplitLAutenticaReceiptFindsTheTotalDespiteADiscountRowAndTrailingBoilerplate() {
        let scan = ReceiptParser.parse(Self.lAutenticaReceipt, now: Self.now)
        #expect(scan.total == 7.22)
        #expect(scan.totalCandidates.isEmpty)
    }

    // Real Vision output (2026-08-28) — a second scan of the *same physical receipt* as
    // `lAutenticaReceipt`, but Vision returned the two columns in the opposite order this time:
    // the price column prints entirely BEFORE "DESCRIZIONE" (right after "PREZZO(E) IVA"), and the
    // label column follows the header instead of preceding it. Also carries a new OCR misread not
    // seen on the first scan: "1.50!" — a VAT class letter recognized as punctuation, not a letter.
    private static let lAutenticaReceiptReversedColumns = [
        "L'AUTENTICH",
        "di MICHALI GIOVANNI",
        "Via P. Togliatti. 29 - Tel. 0836/315585",
        "73040 ARADEO (LE)",
        "C.F.: HGHGNN74E30A350X",
        "P. IVA 04951370750",
        "DOCUMENTO COMMERCIALE",
        "di vendita o prestazione",
        "PREZZO(E) IVA",
        "7.00 L",
        "1.50!",
        "8.50",
        "-1.28",
        "7.22",
        "7.22",
        "0,00",
        "7,22",
        "7.22",
        "2",
        "DESCRIZIONE",
        "REP. SALUMERIA",
        "VIRTUAL",
        "SUBTOTALE",
        "SCONTO 15 DIPENDENTI",
        "SUBTOTALE",
        "TOTALE COMPLESSIVO",
        "DI CUI IVA",
        "PAGAMENTO CONTANTE",
        "IMPORTO PAGATO",
        "NUMERO PEZZI",
        "L: *VI Ventilazione IVA",
        "NUMERO PEZZI",
        "CASSA #1",
        "23/08/26 13:27",
        "RT",
        "2",
        "CASSA",
        "DOC. 0554-0067",
        "96IP3000885",
    ]

    @Test func columnSplitLAutenticaReceiptFindsTheTotalEvenWhenThePriceColumnPrintsBeforeTheHeader() {
        let scan = ReceiptParser.parse(Self.lAutenticaReceiptReversedColumns, now: Self.now)
        #expect(scan.total == 7.22)
        #expect(scan.totalCandidates.isEmpty)
    }

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

    // MARK: - Vision table rows (RecognizeDocumentsRequest)

    @Test func visionTableRowsWinOverTheLineHeuristics() {
        // Flat lines alone leave this ambiguous (two bare amounts, split from their labels), but
        // the rows Vision's own layout analysis paired up resolve it with no column guessing.
        let document = ReceiptDocument(
            lines: ["BAR CENTRALE", "TOTALE COMPLESSIVO", "CONTANTI", "20,00", "13,00"],
            rows: [
                ReceiptRow(label: "CAFFE", amount: 1.20),
                ReceiptRow(label: "TOTALE COMPLESSIVO", amount: 13.00),
                ReceiptRow(label: "CONTANTI", amount: 20.00),
            ]
        )
        let scan = ReceiptParser.parse(document, now: Self.now)
        #expect(scan.total == 13.00)
        #expect(scan.totalCandidates.isEmpty)
    }

    @Test func fallsBackToLineHeuristicsWhenVisionFoundNoTable() {
        let document = ReceiptDocument(lines: Self.barruecoReceipt)
        #expect(ReceiptParser.parse(document, now: Self.now).total == 13.00)
    }

    // MARK: - Data detector results (moneyAmount / calendarEvent)

    @Test func detectedAmountRescuesATotalTheRegexCannotRead() {
        // "TOTALE 13.-" isn't the `d,dd` shape the amount regex requires, but the data detector
        // reads it as money and reports it against that line.
        let document = ReceiptDocument(
            lines: ["NEGOZIO", "TOTALE COMPLESSIVO 13.-"],
            detectedAmounts: [1: 13.00]
        )
        let scan = ReceiptParser.parse(document, now: Self.now)
        #expect(scan.total == 13.00)
    }

    @Test func regexStillWinsOverTheDetectorOnTheSameLine() {
        let document = ReceiptDocument(
            lines: ["NEGOZIO", "TOTALE COMPLESSIVO 13,00"],
            detectedAmounts: [1: 99.00]
        )
        #expect(ReceiptParser.parse(document, now: Self.now).total == 13.00)
    }

    @Test func detectedDateIsUsedOnlyWhenTheRegexFindsNothing() {
        let calendar = Calendar(identifier: .gregorian)
        let detected = DateComponents(calendar: calendar, year: 2026, month: 8, day: 20).date!
        let document = ReceiptDocument(lines: ["NEGOZIO", "TOTALE 5,00"], detectedDates: [detected])
        let scan = ReceiptParser.parse(document, now: Self.now)
        #expect(scan.date == detected)
        #expect(scan.dateWasClamped == false)
    }

    @Test func printedDateOutranksTheDetectedOne() {
        let calendar = Calendar(identifier: .gregorian)
        let printed = DateComponents(calendar: calendar, year: 2026, month: 8, day: 25).date!
        let detectedToday = Self.now
        let document = ReceiptDocument(
            lines: ["NEGOZIO", "25/08/26 19:25", "TOTALE 5,00"],
            detectedDates: [detectedToday]
        )
        #expect(ReceiptParser.parse(document, now: Self.now).date == printed)
    }

    @Test func detectedDateOutsideTheSaneWindowStillClamps() {
        let future = Self.now.addingTimeInterval(60 * 60 * 24 * 30)
        let document = ReceiptDocument(lines: ["NEGOZIO", "TOTALE 5,00"], detectedDates: [future])
        let scan = ReceiptParser.parse(document, now: Self.now)
        #expect(scan.dateWasClamped)
        #expect(scan.date == Self.now)
    }

    // MARK: - Refund detection

    @Test func detectsARefundFromTheDocumentHeader() {
        let lines = ["NEGOZIO", "DOCUMENTO COMMERCIALE di RESO", "TOTALE COMPLESSIVO 12,00"]
        #expect(ReceiptParser.parse(lines, now: Self.now).isRefund)
    }

    @Test func merchantNameContainingTheLettersIsNotARefund() {
        let lines = ["HOTEL RESORT MARINA", "TOTALE COMPLESSIVO 120,00"]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.isRefund == false)
        #expect(scan.total == 120.00)
    }

    @Test func changeDueIsNotARefund() {
        // "Resto" (change) sits one letter away from "Reso" and prints on every cash receipt.
        let lines = ["NEGOZIO", "Pagamento contante 50,50", "Resto 35,30", "TOTALE COMPLESSIVO 15,20"]
        #expect(ReceiptParser.parse(lines, now: Self.now).isRefund == false)
    }

    // MARK: - Ranked total keywords (documento commerciale)

    @Test func mandatedWordingWinsWhenOCRCorruptsTheCorroboratingField() {
        // The failure this ranking exists for: TOTALE COMPLESSIVO and IMPORTO PAGATO print the same
        // amount, and OCR misread one digit of the second. As equal peers that was two disagreeing
        // totals and a "pick one" prompt; the standard says the first field decides.
        let lines = [
            "SUPERMERCATO",
            "TOTALE COMPLESSIVO   15,20",
            "DI CUI IVA            0,00",
            "Importo pagato       16,20",
        ]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.total == 15.20)
        #expect(scan.totalCandidates.isEmpty)
    }

    @Test func looseKeywordsStillCoverSlipsWithoutTheMandatedWording() {
        // A bank POS slip prints neither TOTALE COMPLESSIVO nor IMPORTO PAGATO — the bottom tier
        // has to keep working for it.
        let scan = ReceiptParser.parse(Self.sellaCardSlipReceipt, now: Self.now)
        #expect(scan.total == 41.00)
    }

    @Test func genuinelyDisagreeingTotalsInOneTierStillAskTheUser() {
        // Ranking must not paper over a real conflict: two TOTALE COMPLESSIVO readings that differ
        // are still ambiguous, and the form should show chips rather than pick one.
        let lines = ["NEGOZIO", "TOTALE COMPLESSIVO 15,20", "TOTALE COMPLESSIVO 16,20"]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.total == nil)
        #expect(scan.totalCandidates == [15.20, 16.20])
    }

    // MARK: - Merchant name by text height

    @Test func tallestLineWinsOverUnlistedBoilerplatePrintedAboveTheName() {
        // "SCONTRINO FISCALE" is not in merchantNoisePatterns and would win on "topmost"; the store
        // name below it is printed twice as big, so height settles it with no new list entry.
        let document = ReceiptDocument(
            lines: ["SCONTRINO FISCALE", "PASTICCERIA ROSSI", "VIA ROMA 1", "TOTALE 8,00"],
            lineHeights: [0: 0.010, 1: 0.024, 2: 0.010, 3: 0.012]
        )
        #expect(ReceiptParser.parse(document, now: Self.now).merchant == "Pasticceria Rossi")
    }

    @Test func blocklistStillFiltersEvenWhenTheNoiseIsTheBiggestText() {
        // A card slip carries no merchant name — only the processor's own branding, printed large.
        let document = ReceiptDocument(
            lines: ["MASTERCARD", "PAGAMENTO ELETTRONICO", "TOTALE 8,00"],
            lineHeights: [0: 0.030, 1: 0.010, 2: 0.010]
        )
        #expect(ReceiptParser.parse(document, now: Self.now).merchant == "Pagamento Elettronico")
    }

    @Test func fallsBackToTopmostCandidateWithoutHeights() {
        let document = ReceiptDocument(lines: ["SCONTRINO FISCALE", "PASTICCERIA ROSSI"])
        #expect(ReceiptParser.parse(document, now: Self.now).merchant == "Scontrino Fiscale")
    }

    @Test func returnsNoTotalWhenNothingMatchesAKeyword() {
        let lines = ["NEGOZIO", "articolo 5,00"]
        let scan = ReceiptParser.parse(lines, now: Self.now)
        #expect(scan.total == nil)
        #expect(scan.totalCandidates.isEmpty)
    }
}
