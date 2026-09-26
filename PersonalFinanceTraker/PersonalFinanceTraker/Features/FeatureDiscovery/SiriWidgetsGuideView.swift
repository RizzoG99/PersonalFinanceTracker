import SwiftUI
import UIKit

struct SiriWidgetsGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AccessibilityFocusState private var focusedSection: GuideSection?
    @State private var copiedPhrase: String?

    let media: FeatureDiscoveryManifest.Media?
    let mediaBaseURL: URL?
    var showsDoneButton = false

    private var copy: SiriWidgetsGuideCopy {
        .localized(for: locale)
    }

    private var heroMaximumHeight: CGFloat {
        if verticalSizeClass == .compact { return 160 }
        return horizontalSizeClass == .regular ? 320 : 240
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    FeatureDiscoveryArtworkView(
                        media: media,
                        mediaBaseURL: mediaBaseURL,
                        symbolName: "waveform.path",
                        accessibilityLabel: media?.accessibilityLabel ?? copy.heroAccessibilityLabel,
                        maximumHeight: heroMaximumHeight
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(copy.introductionTitle)
                            .font(.title2.bold())
                            .foregroundStyle(.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        FeatureDiscoveryMarkdownText(copy.introduction)
                            .font(.body)
                            .foregroundStyle(.textMid)
                    }

                    sectionIndex(proxy: proxy)
                    siriSection
                        .id(GuideSection.siri)
                    widgetsSection
                        .id(GuideSection.widgets)
                    stepsSection(
                        section: .home,
                        title: copy.homeScreenTitle,
                        systemImage: "apps.iphone",
                        visualHint: copy.homeScreenVisualHint,
                        illustration: .home,
                        steps: copy.homeScreenSteps
                    )
                    .id(GuideSection.home)
                    stepsSection(
                        section: .lock,
                        title: copy.lockScreenTitle,
                        systemImage: "lock.iphone",
                        visualHint: copy.lockScreenVisualHint,
                        illustration: .lock,
                        steps: copy.lockScreenSteps
                    )
                    .id(GuideSection.lock)
                    privacySection
                    completionButton
                }
                .padding(20)
                .readableWidth(760)
            }
        }
        .appBackground()
        .navigationTitle(copy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copiedPhrase)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.doneTitle) { dismiss() }
                }
            }
        }
    }

    private func sectionIndex(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy.contentsTitle)
                .font(.subheadline.bold())
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    sectionButton(copy.siriShortTitle, systemImage: "waveform", section: .siri, proxy: proxy)
                    sectionButton(copy.widgetsShortTitle, systemImage: "square.grid.2x2", section: .widgets, proxy: proxy)
                    sectionButton(copy.homeShortTitle, systemImage: "apps.iphone", section: .home, proxy: proxy)
                    sectionButton(copy.lockShortTitle, systemImage: "lock.iphone", section: .lock, proxy: proxy)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func sectionButton(
        _ title: String,
        systemImage: String,
        section: GuideSection,
        proxy: ScrollViewProxy
    ) -> some View {
        Button {
            if reduceMotion {
                proxy.scrollTo(section, anchor: .top)
            } else {
                withAnimation(.snappy) {
                    proxy.scrollTo(section, anchor: .top)
                }
            }
            focusedSection = section
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.surfaceRaised, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.hairline, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(GuideSectionButtonStyle())
        .accessibilityLabel("\(copy.jumpToTitle) \(title)")
    }

    private var siriSection: some View {
        guideCard(section: .siri, title: copy.siriTitle, systemImage: "waveform") {
            FeatureDiscoveryMarkdownText(copy.siriIntroduction)
                .foregroundStyle(.textMid)

            Text(copy.exactPhrasesTitle)
                .font(.subheadline.bold())
                .foregroundStyle(.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(copy.siriPhrases, id: \.self) { phrase in
                    SiriPhraseRow(
                        phrase: phrase,
                        copyTitle: copy.copyTitle,
                        copiedTitle: copy.copiedTitle,
                        exactPhraseAccessibilityLabel: copy.exactPhraseAccessibilityLabel,
                        isCopied: copiedPhrase == phrase
                    ) {
                        UIPasteboard.general.string = phrase
                        copiedPhrase = phrase
                    }
                }
            }

            Label(copy.siriCompletion, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.textMid)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var widgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(copy.widgetsTitle, systemImage: "square.grid.2x2")
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedSection, equals: .widgets)

            Text(copy.widgetsIntroduction)
                .font(.subheadline)
                .foregroundStyle(.textMid)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(copy.widgets) { widget in
                    SiriWidgetPreviewCard(widget: widget, previewTitle: copy.previewTitle)
                }
            }
        }
    }

    private func stepsSection(
        section: GuideSection,
        title: String,
        systemImage: String,
        visualHint: String,
        illustration: GuideSetupIllustration.Kind,
        steps: [String]
    ) -> some View {
        guideCard(section: section, title: title, systemImage: systemImage) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    GuideSetupIllustration(kind: illustration)
                    Text(visualHint)
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    GuideSetupIllustration(kind: illustration)
                    Text(visualHint)
                        .font(.subheadline)
                        .foregroundStyle(.textMid)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.primaryActionForeground)
                            .frame(width: 28, height: 28)
                            .background(.accentIndigo, in: Circle())
                            .accessibilityHidden(true)
                        FeatureDiscoveryMarkdownText(step)
                            .foregroundStyle(.textMid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(index + 1). \(plainText(step))")
                }
            }
        }
    }

    private var privacySection: some View {
        guideCard(section: nil, title: copy.privacyTitle, systemImage: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(copy.privacyBullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.categoryTeal)
                            .accessibilityHidden(true)
                        FeatureDiscoveryMarkdownText(bullet)
                            .foregroundStyle(.textMid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var completionButton: some View {
        Button {
            dismiss()
        } label: {
            Label(copy.doneTitle, systemImage: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primaryActionForeground)
                .frame(maxWidth: .infinity, minHeight: 52)
                .glassEffect(.regular.tint(.accentIndigo).interactive(), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("siriWidgetsGuide.done")
    }

    private func guideCard<Content: View>(
        section: GuideSection?,
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                guideHeading(title: title, systemImage: systemImage, section: section)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func guideHeading(title: String, systemImage: String, section: GuideSection?) -> some View {
        if let section {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedSection, equals: section)
        } else {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func plainText(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "**", with: "")
    }
}

private enum GuideSection: String, Hashable {
    case siri, widgets, home, lock
}

private struct SiriPhraseRow: View {
    let phrase: String
    let copyTitle: String
    let copiedTitle: String
    let exactPhraseAccessibilityLabel: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                phraseLabel
                Spacer(minLength: 4)
                copyButton
            }

            VStack(alignment: .leading, spacing: 10) {
                phraseLabel
                copyButton
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }

    private var phraseLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "quote.opening")
                .foregroundStyle(.accentIndigo)
                .accessibilityHidden(true)
            Text(phrase)
                .font(.body.weight(.medium))
                .foregroundStyle(.textPrimary)
                .accessibilityLabel("\(exactPhraseAccessibilityLabel): \(phrase)")
        }
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            Label(isCopied ? copiedTitle : copyTitle, systemImage: isCopied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 44)
    }
}

private struct GuideSectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct SiriWidgetPreviewCard: View {
    let widget: SiriWidgetsGuideCopy.Widget
    let previewTitle: String

    var body: some View {
        GlassCard(tint: widget.tint.opacity(0.1), borderRadius: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    widgetPreview
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    previewCopy
                }

                VStack(alignment: .leading, spacing: 12) {
                    widgetPreview
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .accessibilityHidden(true)
                    previewCopy
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(previewTitle). \(widget.title)")
        .accessibilityValue("\(widget.description) \(widget.availability)")
    }

    private var previewCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(previewTitle)
                .font(.caption.bold())
                .foregroundStyle(.accentIndigo)
            Text(widget.title)
                .font(.subheadline.bold())
                .foregroundStyle(.textPrimary)
            Text(widget.description)
                .font(.subheadline)
                .foregroundStyle(.textMid)
            Label(widget.availability, systemImage: "rectangle.on.rectangle")
                .font(.caption)
                .foregroundStyle(.textMid)
        }
    }

    @ViewBuilder
    private var widgetPreview: some View {
        switch widget.kind {
        case .pulse:
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundStyle(.accentIndigo)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? Color.categoryTeal : Color.hairline)
                            .frame(width: 14, height: 14)
                    }
                }
            }
        case .receipt:
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentIndigo, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(width: 72, height: 72)
                Image(systemName: "doc.text.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.categoryTeal)
            }
        case .safeToSpend:
            ZStack {
                Circle()
                    .stroke(Color.hairline, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(Color.categoryTeal, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.headline.bold())
                    .foregroundStyle(.accentIndigo)
            }
            .frame(width: 70, height: 70)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct GuideSetupIllustration: View {
    enum Kind {
        case home, lock
    }

    let kind: Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.hairline, lineWidth: 2)
                .frame(width: 70, height: 104)

            switch kind {
            case .home:
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 6), count: 3), spacing: 6) {
                    ForEach(0..<6, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == 1 ? Color.categoryTeal : Color.accentIndigo.opacity(0.35))
                            .frame(width: 12, height: 12)
                    }
                }
                .frame(width: 48)

                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.accentIndigo)
                    .background(.surfaceRaised, in: Circle())
                    .offset(x: 30, y: -45)
            case .lock:
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.textMid)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentIndigo.opacity(0.2))
                        .frame(width: 46, height: 24)
                        .overlay {
                            HStack(spacing: 4) {
                                Circle().fill(Color.categoryTeal).frame(width: 8, height: 8)
                                Circle().fill(Color.accentIndigo).frame(width: 8, height: 8)
                            }
                        }
                }
            }
        }
        .frame(width: 88, height: 116)
        .accessibilityHidden(true)
    }
}

struct SiriWidgetsGuideCopy {
    struct Widget: Identifiable {
        enum Kind {
            case pulse
            case receipt
            case safeToSpend
        }

        let id: String
        let kind: Kind
        let title: String
        let description: String
        let availability: String
        let tint: Color
    }

    let navigationTitle: String
    let doneTitle: String
    let heroAccessibilityLabel: String
    let introductionTitle: String
    let introduction: String
    let contentsTitle: String
    let jumpToTitle: String
    let siriShortTitle: String
    let widgetsShortTitle: String
    let homeShortTitle: String
    let lockShortTitle: String
    let siriTitle: String
    let siriIntroduction: String
    let exactPhrasesTitle: String
    let exactPhraseAccessibilityLabel: String
    let copyTitle: String
    let copiedTitle: String
    let siriCompletion: String
    let siriPhrases: [String]
    let widgetsTitle: String
    let widgetsIntroduction: String
    let previewTitle: String
    let widgets: [Widget]
    let homeScreenTitle: String
    let homeScreenVisualHint: String
    let homeScreenSteps: [String]
    let lockScreenTitle: String
    let lockScreenVisualHint: String
    let lockScreenSteps: [String]
    let privacyTitle: String
    let privacyBullets: [String]

    static func localized(for locale: Locale) -> Self {
        locale.language.languageCode?.identifier == "it" ? italian : english
    }

    private static let english = Self(
        navigationTitle: "Siri & Widgets",
        doneTitle: "Done",
        heroAccessibilityLabel: "An abstract indigo voice waveform beside three floating glass widget tiles.",
        introductionTitle: "Useful shortcuts, right where you need them",
        introduction: "Use **Siri** to log a transaction by voice, and add **Personal Finance widgets** to your Home Screen or Lock Screen.",
        contentsTitle: "In this guide",
        jumpToTitle: "Jump to",
        siriShortTitle: "Siri",
        widgetsShortTitle: "Widgets",
        homeShortTitle: "Home Screen",
        lockShortTitle: "Lock Screen",
        siriTitle: "Add transactions with Siri",
        siriIntroduction: "Try one of these exact phrases. **Siri** then asks for the amount, category, transaction type, and an optional note.",
        exactPhrasesTitle: "Try saying",
        exactPhraseAccessibilityLabel: "Exact Siri phrase",
        copyTitle: "Copy",
        copiedTitle: "Copied",
        siriCompletion: "After you answer, Siri saves the transaction and confirms it.",
        siriPhrases: [
            "Add a transaction in Personal Finance",
            "Log an expense in Personal Finance",
        ],
        widgetsTitle: "Choose your widget",
        widgetsIntroduction: "These are previews. Availability shows where each widget appears and which sizes you can choose.",
        previewTitle: "Preview",
        widgets: [
            Widget(
                id: "financial-pulse",
                kind: .pulse,
                title: "Financial Pulse",
                description: "Check in with today’s spending and keep your logging habit moving.",
                availability: "Home: Small or Medium · Lock: Circular",
                tint: .accentIndigo
            ),
            Widget(
                id: "scan-receipt",
                kind: .receipt,
                title: "Scan Receipt",
                description: "Jump directly to receipt scanning from your Home or Lock Screen.",
                availability: "Home: Small · Lock: Circular",
                tint: .categoryTeal
            ),
            Widget(
                id: "safe-to-spend",
                kind: .safeToSpend,
                title: "Safe to Spend",
                description: "See your daily spending room at a glance on the Home Screen.",
                availability: "Home: Small",
                tint: .categoryGreen
            ),
        ],
        homeScreenTitle: "Add a Home Screen widget",
        homeScreenVisualHint: "Edit the Home Screen, open the widget gallery, and search for Personal Finance.",
        homeScreenSteps: [
            "Touch and hold an empty area of the Home Screen.",
            "Tap **Edit**, then **Add Widget**.",
            "Search for Personal Finance.",
            "Choose a widget and size, then tap **Add Widget**.",
        ],
        lockScreenTitle: "Add a Lock Screen widget",
        lockScreenVisualHint: "Customize the Lock Screen and select the widget area below the clock.",
        lockScreenSteps: [
            "Touch and hold the Lock Screen, then tap **Customize**.",
            "Choose **Lock Screen** and tap the widget area below the clock.",
            "Find Personal Finance and choose an available widget.",
            "Tap **Done** to save the Lock Screen.",
        ],
        privacyTitle: "Your privacy",
        privacyBullets: [
            "**Siri and widgets use data already stored by Personal Finance.**",
            "Financial Pulse and Scan Receipt do not show amounts.",
            "Safe to Spend may show an amount. It is privacy-sensitive, so iOS can conceal it based on your Lock Screen privacy settings.",
        ]
    )

    private static let italian = Self(
        navigationTitle: "Siri e widget",
        doneTitle: "Fine",
        heroAccessibilityLabel: "Una forma d’onda vocale indaco accanto a tre widget in vetro sospesi.",
        introductionTitle: "Scorciatoie utili, sempre a portata di mano",
        introduction: "Usa **Siri** per registrare una transazione con la voce e aggiungi i **widget di Personal Finance** alla schermata Home o di blocco.",
        contentsTitle: "In questa guida",
        jumpToTitle: "Vai a",
        siriShortTitle: "Siri",
        widgetsShortTitle: "Widget",
        homeShortTitle: "Home",
        lockShortTitle: "Blocco",
        siriTitle: "Aggiungi transazioni con Siri",
        siriIntroduction: "Prova una di queste frasi esatte. **Siri** ti chiederà importo, categoria, tipo di transazione e una nota facoltativa.",
        exactPhrasesTitle: "Prova a dire",
        exactPhraseAccessibilityLabel: "Frase esatta per Siri",
        copyTitle: "Copia",
        copiedTitle: "Copiata",
        siriCompletion: "Dopo le tue risposte, Siri salva la transazione e la conferma.",
        siriPhrases: [
            "Aggiungi una transazione con Personal Finance",
            "Registra una spesa con Personal Finance",
        ],
        widgetsTitle: "Scegli il widget",
        widgetsIntroduction: "Queste sono anteprime. La disponibilità indica dove appare ogni widget e quali dimensioni puoi scegliere.",
        previewTitle: "Anteprima",
        widgets: [
            Widget(
                id: "financial-pulse",
                kind: .pulse,
                title: "Impulso finanziario",
                description: "Controlla le spese di oggi e mantieni attiva l’abitudine di registrarle.",
                availability: "Home: piccolo o medio · Blocco: circolare",
                tint: .accentIndigo
            ),
            Widget(
                id: "scan-receipt",
                kind: .receipt,
                title: "Scansiona uno scontrino",
                description: "Avvia direttamente la scansione dalla schermata Home o di blocco.",
                availability: "Home: piccolo · Blocco: circolare",
                tint: .categoryTeal
            ),
            Widget(
                id: "safe-to-spend",
                kind: .safeToSpend,
                title: "Quanto puoi spendere",
                description: "Controlla a colpo d’occhio il margine di spesa giornaliero nella schermata Home.",
                availability: "Home: piccolo",
                tint: .categoryGreen
            ),
        ],
        homeScreenTitle: "Aggiungi un widget alla schermata Home",
        homeScreenVisualHint: "Modifica la schermata Home, apri la galleria dei widget e cerca Personal Finance.",
        homeScreenSteps: [
            "Tieni premuto uno spazio vuoto sulla schermata Home.",
            "Tocca **Modifica**, poi **Aggiungi widget**.",
            "Cerca Personal Finance.",
            "Scegli un widget e una dimensione, poi tocca **Aggiungi widget**.",
        ],
        lockScreenTitle: "Aggiungi un widget alla schermata di blocco",
        lockScreenVisualHint: "Personalizza la schermata di blocco e seleziona l’area dei widget sotto l’orologio.",
        lockScreenSteps: [
            "Tieni premuta la schermata di blocco, poi tocca **Personalizza**.",
            "Scegli **Schermata di blocco** e tocca l’area dei widget sotto l’orologio.",
            "Trova Personal Finance e scegli un widget disponibile.",
            "Tocca **Fine** per salvare la schermata di blocco.",
        ],
        privacyTitle: "La tua privacy",
        privacyBullets: [
            "**Siri e i widget usano i dati già archiviati in Personal Finance.**",
            "Impulso finanziario e Scansiona uno scontrino non mostrano importi.",
            "Quanto puoi spendere può mostrare un importo. È un dato sensibile, quindi iOS può nasconderlo in base alle impostazioni di privacy della schermata di blocco.",
        ]
    )
}

extension FeatureDiscoveryManifest {
    var siriWidgetsGuideMedia: Media? {
        releases
            .flatMap(\.items)
            .first(where: { $0.destination == .siriWidgetsGuide })?
            .media
    }
}

#Preview("English") {
    NavigationStack {
        SiriWidgetsGuideView(media: nil, mediaBaseURL: nil)
    }
    .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Italian") {
    NavigationStack {
        SiriWidgetsGuideView(media: nil, mediaBaseURL: nil)
    }
    .environment(\.locale, Locale(identifier: "it"))
}
