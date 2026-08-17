import Foundation
import Testing
@testable import PersonalFinanceTraker

struct FeatureDiscoveryCoordinatorTests {
    @Test @MainActor func firstEligibleLaunchShowsTourBeforeReleaseNotes() {
        let defaults = makeDefaults()
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")

        #expect(coordinator.isShowingTour)
        #expect(coordinator.releaseToPresent == nil)
    }

    @Test @MainActor func returningUserSeesCurrentReleaseOnlyOnce() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "feature_discovery_has_completed_tour")
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(coordinator.releaseToPresent?.version == "1.0")

        coordinator.dismissWhatsNew()
        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(coordinator.releaseToPresent == nil)
    }

    @Test @MainActor func manualReleasePresentationIgnoresSeenState() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "feature_discovery_has_completed_tour")
        defaults.set("1.0", forKey: "feature_discovery_last_seen_release_version")
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        coordinator.showWhatsNew(appVersion: "1.0")

        #expect(coordinator.releaseToPresent?.id == "1.0-financial-pulse")
    }

    @Test @MainActor func finishingTourQueuesFirstTransactionAction() {
        let coordinator = FeatureDiscoveryCoordinator(defaults: makeDefaults())

        coordinator.finishTour(destination: .addTransaction)

        #expect(coordinator.consumeDestination() == .addTransaction)
        #expect(coordinator.consumeDestination() == nil)
    }

    @Test func italianFallbackCopyKeepsRemoteArtwork() {
        let remoteMedia = FeatureDiscoveryManifest.Media(
            kind: .image,
            path: "onboarding/overview-v1.png",
            accessibilityLabel: "English media description"
        )
        let page = FeatureDiscoveryManifest.Page(
            id: "overview",
            title: "Your money, in one place",
            body: "English body",
            symbolName: "sparkles",
            media: remoteMedia,
            destination: .home
        )
        let manifest = FeatureDiscoveryManifest(
            schemaVersion: 1,
            contentVersion: "test",
            onboarding: .init(id: "explore-the-app", title: "Explore Personal Finance", pages: [page]),
            releases: []
        )

        let localized = manifest.applyingBuiltInCopy(for: "it")

        #expect(localized.onboarding.title == "Scopri Personal Finance")
        #expect(localized.onboarding.pages[0].title == "Tutto il tuo denaro, in un unico posto")
        #expect(localized.onboarding.pages[0].media?.path == "onboarding/overview-v1.png")
    }

    @Test func fallbackIncludesTheFinancialPulseRelease() {
        let release = FeatureDiscoveryManifest.fallback.releases.last

        #expect(release?.id == "1.0-financial-pulse")
        #expect(release?.items.map(\.destination) == [.home, .insights])
    }

    private var fallbackContent: FeatureDiscoveryLoadedContent {
        FeatureDiscoveryLoadedContent(manifest: .fallback, mediaBaseURL: nil)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FeatureDiscoveryCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
