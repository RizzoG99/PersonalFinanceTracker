import SwiftUI

struct FeatureDiscoveryTourView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let onboarding: FeatureDiscoveryManifest.Onboarding
    let mediaBaseURL: URL?
    let onFinish: (FeatureDiscoveryDestination) -> Void

    @State private var selectedPage = 0

    private var isLastPage: Bool {
        selectedPage == onboarding.pages.count - 1
    }

    private var compactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                FeatureDiscoveryTourHeader(
                    title: onboarding.title,
                    showsBackButton: selectedPage > 0,
                    compactHeight: compactHeight,
                    onBack: showPreviousPage,
                    onSkip: skipTour
                )

                TabView(selection: $selectedPage) {
                    ForEach(Array(onboarding.pages.enumerated()), id: \.element.id) { index, page in
                        FeatureDiscoveryTourPage(
                            page: page,
                            mediaBaseURL: mediaBaseURL
                        )
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FeatureDiscoveryTourControls(
                currentPage: selectedPage,
                pageCount: onboarding.pages.count,
                actionTitle: isLastPage ? "Add Transaction" : "Continue",
                compactHeight: compactHeight,
                onAdvance: advance
            )
        }
    }

    private func showPreviousPage() {
        guard selectedPage > 0 else { return }
        selectedPage -= 1
    }

    private func skipTour() {
        onFinish(.home)
    }

    private func advance() {
        if isLastPage {
            onFinish(.addTransaction)
        } else {
            withAnimation(.snappy) {
                selectedPage += 1
            }
        }
    }
}

private struct FeatureDiscoveryTourHeader: View {
    let title: String
    let showsBackButton: Bool
    let compactHeight: Bool
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showsBackButton {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Go back")
            }

            Text(title)
                .font(compactHeight ? .subheadline.bold() : .headline)
                .foregroundStyle(.textPrimary)
                .lineLimit(compactHeight ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSkip) {
                Text("Skip")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, compactHeight ? 4 : 8)
    }
}

private struct FeatureDiscoveryTourPage: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let page: FeatureDiscoveryManifest.Page
    let mediaBaseURL: URL?

    var body: some View {
        GeometryReader { proxy in
            FeatureDiscoveryTourPageContent(
                page: page,
                mediaBaseURL: mediaBaseURL,
                layout: FeatureDiscoveryPageLayout(
                    availableSize: proxy.size,
                    horizontalSizeClass: horizontalSizeClass,
                    verticalSizeClass: verticalSizeClass
                )
            )
        }
    }
}

private struct FeatureDiscoveryTourPageContent: View {
    let page: FeatureDiscoveryManifest.Page
    let mediaBaseURL: URL?
    let layout: FeatureDiscoveryPageLayout

    var body: some View {
        ScrollView {
            Group {
                if layout.usesTwoColumns {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        HStack(spacing: 24) {
                            FeatureDiscoveryArtworkView(
                                media: page.media,
                                mediaBaseURL: mediaBaseURL,
                                symbolName: page.symbolName,
                                accessibilityLabel: page.media?.accessibilityLabel ?? page.title,
                                width: layout.artworkWidth,
                                maximumHeight: layout.artworkHeight
                            )

                            FeatureDiscoveryTourCopy(page: page, usesTwoColumns: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: layout.artworkHeight)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: layout.contentHeight)
                } else {
                    VStack(spacing: 20) {
                        FeatureDiscoveryArtworkView(
                            media: page.media,
                            mediaBaseURL: mediaBaseURL,
                            symbolName: page.symbolName,
                            accessibilityLabel: page.media?.accessibilityLabel ?? page.title,
                            width: layout.artworkWidth,
                            maximumHeight: layout.artworkHeight
                        )

                        FeatureDiscoveryTourCopy(page: page, usesTwoColumns: false)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, layout.verticalPadding)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureDiscoveryTourCopy: View {
    let page: FeatureDiscoveryManifest.Page
    let usesTwoColumns: Bool

    var body: some View {
        VStack(alignment: usesTwoColumns ? .leading : .center, spacing: 12) {
            Text(page.title)
                .font(usesTwoColumns ? .title2.bold() : .title.bold())
                .multilineTextAlignment(usesTwoColumns ? .leading : .center)
                .foregroundStyle(.textPrimary)
            Text(page.body)
                .font(.body)
                .multilineTextAlignment(usesTwoColumns ? .leading : .center)
                .foregroundStyle(.textMid)
                .frame(maxWidth: 360, alignment: usesTwoColumns ? .leading : .center)
        }
    }
}

private struct FeatureDiscoveryPageLayout {
    let usesTwoColumns: Bool
    let artworkWidth: CGFloat
    let artworkHeight: CGFloat
    let verticalPadding: CGFloat
    let contentHeight: CGFloat

    init(
        availableSize: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) {
        let contentWidth = max(availableSize.width - 48, 0)
        let isWideViewport = availableSize.width > availableSize.height
        let padding: CGFloat
        usesTwoColumns = isWideViewport || (horizontalSizeClass == .regular && contentWidth >= 700)

        if usesTwoColumns {
            artworkWidth = min(max(contentWidth * 0.36, 220), 420)
            artworkHeight = min(max(availableSize.height * 0.7, 160), 315)
            padding = verticalSizeClass == .compact ? 16 : 24
        } else {
            artworkWidth = min(contentWidth, 640)
            artworkHeight = min(artworkWidth * 0.75, 480)
            padding = 28
        }

        verticalPadding = padding
        contentHeight = max(availableSize.height - (padding * 2), 0)
    }
}

private struct FeatureDiscoveryTourControls: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let currentPage: Int
    let pageCount: Int
    let actionTitle: LocalizedStringKey
    let compactHeight: Bool
    let onAdvance: () -> Void

    var body: some View {
        Group {
            if compactHeight {
                HStack(spacing: 14) {
                    FeatureDiscoveryProgress(currentPage: currentPage, pageCount: pageCount)
                    FeatureDiscoveryAdvanceButton(title: actionTitle, action: onAdvance)
                }
            } else {
                VStack(spacing: 14) {
                    FeatureDiscoveryProgress(currentPage: currentPage, pageCount: pageCount)
                    FeatureDiscoveryAdvanceButton(
                        title: actionTitle,
                        maximumWidth: horizontalSizeClass == .regular ? 640 : nil,
                        action: onAdvance
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, compactHeight ? 4 : 8)
        .padding(.bottom, 8)
    }
}

private struct FeatureDiscoveryProgress: View {
    let currentPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(currentPage + 1) / \(pageCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.textMid)

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentIndigo : Color.hairline)
                        .frame(width: index == currentPage ? 22 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Color.surfaceRaised), in: Capsule())
    }
}

private struct FeatureDiscoveryAdvanceButton: View {
    let title: LocalizedStringKey
    let maximumWidth: CGFloat?
    let action: () -> Void

    init(title: LocalizedStringKey, maximumWidth: CGFloat? = nil, action: @escaping () -> Void) {
        self.title = title
        self.maximumWidth = maximumWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(.primaryActionForeground)
                .frame(maxWidth: .infinity, minHeight: 52)
                .glassEffect(.regular.tint(.accentIndigo).interactive(), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: maximumWidth)
        .accessibilityIdentifier("featureDiscovery.advance")
    }
}

struct FeatureDiscoveryWhatsNewView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let release: FeatureDiscoveryManifest.Release
    let mediaBaseURL: URL?
    let onAction: (FeatureDiscoveryDestination?) -> Void
    let onDone: () -> Void

    private var compactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var usesHorizontalCards: Bool {
        compactHeight || horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(release.title)
                        .font(compactHeight ? .title2.bold() : .title.bold())
                        .foregroundStyle(.textPrimary)
                    Text(release.summary)
                        .foregroundStyle(.textMid)

                    ForEach(release.items) { item in
                        FeatureDiscoveryReleaseItemView(
                            item: item,
                            mediaBaseURL: mediaBaseURL,
                            usesHorizontalLayout: usesHorizontalCards,
                            artworkWidth: horizontalSizeClass == .regular ? 220 : 176
                        ) {
                            onAction(item.destination)
                        }
                    }
                }
                .padding(20)
            }
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

private struct FeatureDiscoveryReleaseItemView: View {
    let item: FeatureDiscoveryManifest.ReleaseItem
    let mediaBaseURL: URL?
    let usesHorizontalLayout: Bool
    let artworkWidth: CGFloat
    let onAction: () -> Void

    var body: some View {
        Group {
            if usesHorizontalLayout {
                HStack(alignment: .top, spacing: 16) {
                    FeatureDiscoveryArtworkView(
                        media: item.media,
                        mediaBaseURL: mediaBaseURL,
                        symbolName: item.symbolName,
                        accessibilityLabel: item.media?.accessibilityLabel ?? item.title,
                        width: artworkWidth,
                        maximumHeight: artworkWidth * 0.75
                    )
                    FeatureDiscoveryReleaseCopy(item: item, onAction: onAction)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    FeatureDiscoveryArtworkView(
                        media: item.media,
                        mediaBaseURL: mediaBaseURL,
                        symbolName: item.symbolName,
                        accessibilityLabel: item.media?.accessibilityLabel ?? item.title
                    )
                    FeatureDiscoveryReleaseCopy(item: item, onAction: onAction)
                }
            }
        }
        .padding(usesHorizontalLayout ? 14 : 16)
        .background(.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct FeatureDiscoveryReleaseCopy: View {
    let item: FeatureDiscoveryManifest.ReleaseItem
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.textPrimary)
            Text(item.body)
                .foregroundStyle(.textMid)
            if let actionTitle = item.actionTitle {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.bordered)
                    .tint(.accentIndigo)
            }
        }
    }
}

private struct FeatureDiscoveryArtworkView: View {
    let media: FeatureDiscoveryManifest.Media?
    let mediaBaseURL: URL?
    let symbolName: String
    let accessibilityLabel: String
    let width: CGFloat?
    let maximumHeight: CGFloat?

    init(
        media: FeatureDiscoveryManifest.Media?,
        mediaBaseURL: URL?,
        symbolName: String,
        accessibilityLabel: String,
        width: CGFloat? = nil,
        maximumHeight: CGFloat? = nil
    ) {
        self.media = media
        self.mediaBaseURL = mediaBaseURL
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        self.width = width
        self.maximumHeight = maximumHeight
    }

    var body: some View {
        Group {
            if let url = media?.url(relativeTo: mediaBaseURL), media?.kind == .image {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(width: width, height: renderedHeight)
        .clipShape(artworkShape)
        .accessibilityLabel(accessibilityLabel)
    }

    private var artworkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: artworkCornerRadius)
    }

    private var artworkCornerRadius: CGFloat {
        let renderedWidth = width ?? maximumHeight.map { $0 * (4.0 / 3.0) } ?? 360
        return min(max(renderedWidth * 0.08, 24), 36)
    }

    private var renderedHeight: CGFloat? {
        guard let width else { return maximumHeight }
        return min(width * 0.75, maximumHeight ?? .greatestFiniteMagnitude)
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [.accentIndigo.opacity(0.18), .categoryTeal.opacity(0.12), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbolName)
                .font(.system(size: 68, weight: .medium))
                .foregroundStyle(.accentIndigo)
                .symbolRenderingMode(.hierarchical)
        }
        .background(.surfaceRaised)
    }
}
