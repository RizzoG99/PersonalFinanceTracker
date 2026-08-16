import SwiftUI

struct FeatureDiscoveryTourView: View {
    let onboarding: FeatureDiscoveryManifest.Onboarding
    let mediaBaseURL: URL?
    let onFinish: (FeatureDiscoveryDestination) -> Void

    @State private var selectedPage = 0

    private var isLastPage: Bool {
        selectedPage == onboarding.pages.count - 1
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                FeatureDiscoveryTourHeader(
                    title: onboarding.title,
                    showsBackButton: selectedPage > 0,
                    onBack: showPreviousPage,
                    onSkip: skipTour
                )

                TabView(selection: $selectedPage) {
                    ForEach(Array(onboarding.pages.enumerated()), id: \.element.id) { index, page in
                        FeatureDiscoveryTourPage(page: page, mediaBaseURL: mediaBaseURL)
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
            selectedPage += 1
        }
    }
}

private struct FeatureDiscoveryTourHeader: View {
    let title: String
    let showsBackButton: Bool
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
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Skip", action: onSkip)
                .font(.body.weight(.semibold))
                .foregroundStyle(.textPrimary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

private struct FeatureDiscoveryTourPage: View {
    let page: FeatureDiscoveryManifest.Page
    let mediaBaseURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FeatureDiscoveryArtworkView(
                    media: page.media,
                    mediaBaseURL: mediaBaseURL,
                    symbolName: page.symbolName,
                    accessibilityLabel: page.media?.accessibilityLabel ?? page.title
                )

                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.textPrimary)
                    Text(page.body)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.textMid)
                        .frame(maxWidth: 360)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FeatureDiscoveryTourControls: View {
    let currentPage: Int
    let pageCount: Int
    let actionTitle: LocalizedStringKey
    let onAdvance: () -> Void

    var body: some View {
        VStack(spacing: 14) {
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

            Button(action: onAdvance) {
                Text(actionTitle)
                    .foregroundStyle(.primaryActionForeground)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentIndigo).interactive(), in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

struct FeatureDiscoveryWhatsNewView: View {
    let release: FeatureDiscoveryManifest.Release
    let mediaBaseURL: URL?
    let onAction: (FeatureDiscoveryDestination?) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(release.title)
                        .font(.title.bold())
                        .foregroundStyle(.textPrimary)
                    Text(release.summary)
                        .foregroundStyle(.textMid)

                    ForEach(release.items) { item in
                        FeatureDiscoveryReleaseItemView(item: item, mediaBaseURL: mediaBaseURL) {
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
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureDiscoveryArtworkView(
                media: item.media,
                mediaBaseURL: mediaBaseURL,
                symbolName: item.symbolName,
                accessibilityLabel: item.media?.accessibilityLabel ?? item.title
            )
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
        .padding(16)
        .background(.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct FeatureDiscoveryArtworkView: View {
    let media: FeatureDiscoveryManifest.Media?
    let mediaBaseURL: URL?
    let symbolName: String
    let accessibilityLabel: String

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
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityLabel(accessibilityLabel)
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
