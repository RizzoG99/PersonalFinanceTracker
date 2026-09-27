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

    @Test @MainActor func legacyVersionStateSkipsOldReleaseButShowsNewRelease() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "feature_discovery_has_completed_tour")
        defaults.set("1.0", forKey: "feature_discovery_last_seen_release_version")
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: oldReleaseContent, appVersion: "1.0")
        #expect(coordinator.releaseToPresent == nil)
        #expect(defaults.string(forKey: "feature_discovery_last_seen_release_id") == "1.0-financial-pulse")

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(coordinator.releaseToPresent?.id == "1.0-highlights-2026-09")
    }

    @Test @MainActor func returningUserSeesNewReleaseOnlyOnceAndDismissalPersistsItsID() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "feature_discovery_has_completed_tour")
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(coordinator.releaseToPresent?.id == "1.0-highlights-2026-09")

        coordinator.dismissWhatsNew()
        #expect(defaults.string(forKey: "feature_discovery_last_seen_release_id") == "1.0-highlights-2026-09")

        let nextLaunch = FeatureDiscoveryCoordinator(defaults: defaults)
        nextLaunch.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(nextLaunch.releaseToPresent == nil)
    }

    @Test @MainActor func manualReleasePresentationIgnoresSeenState() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "feature_discovery_has_completed_tour")
        defaults.set("1.0-highlights-2026-09", forKey: "feature_discovery_last_seen_release_id")
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        coordinator.showWhatsNew(appVersion: "1.0")

        #expect(coordinator.releaseToPresent?.id == "1.0-highlights-2026-09")
        #expect(coordinator.hasUnseenRelease == false)
    }

    @Test @MainActor func unseenReleaseBadgeClearsOnDismissalAndStaysClearedAcrossLaunches() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "feature_discovery_has_completed_tour")
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(coordinator.hasUnseenRelease)

        coordinator.dismissWhatsNew()
        #expect(coordinator.hasUnseenRelease == false)

        let nextLaunch = FeatureDiscoveryCoordinator(defaults: defaults)
        nextLaunch.prepare(content: fallbackContent, appVersion: "1.0")
        #expect(nextLaunch.hasUnseenRelease == false)
    }

    @Test @MainActor func unseenReleaseBadgeSurvivesTheOnboardingTourDeferral() {
        let defaults = makeDefaults()
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        coordinator.prepare(content: fallbackContent, appVersion: "1.0")

        #expect(coordinator.isShowingTour)
        #expect(coordinator.releaseToPresent == nil)
        #expect(coordinator.hasUnseenRelease)
    }

    @Test @MainActor func finishingTourQueuesFirstTransactionAction() {
        let coordinator = FeatureDiscoveryCoordinator(defaults: makeDefaults())

        coordinator.finishTour(destination: .addTransaction)

        #expect(coordinator.consumeDestination() == .addTransaction)
        #expect(coordinator.consumeDestination() == nil)
    }

    @Test @MainActor func everyNewReleaseActionQueuesItsDestinationAfterDismissal() {
        let defaults = makeDefaults()
        let coordinator = FeatureDiscoveryCoordinator(defaults: defaults)

        for destination in [FeatureDiscoveryDestination.travels, .receiptScan, .recurring, .siriWidgetsGuide] {
            coordinator.showWhatsNew(appVersion: "1.0")
            coordinator.performReleaseAction(destination: destination)
            #expect(coordinator.consumeDestination() == nil)

            coordinator.completeWhatsNewDismissal()
            #expect(coordinator.consumeDestination() == destination)
            #expect(coordinator.consumeDestination() == nil)
        }
    }

    @Test func newDestinationValuesDecodeFromTheRemoteContract() throws {
        let data = Data(#"["travels","receiptScan","recurring","siriWidgetsGuide"]"#.utf8)

        let destinations = try JSONDecoder().decode([FeatureDiscoveryDestination].self, from: data)

        #expect(destinations == [.travels, .receiptScan, .recurring, .siriWidgetsGuide])
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

    @Test func fallbackIncludesTheNewHighlightsRelease() {
        let release = FeatureDiscoveryManifest.fallback(for: "en").releases.last

        #expect(release?.id == "1.0-highlights-2026-09")
        #expect(release?.items.map(\.destination) == [.travels, .receiptScan, .recurring, .siriWidgetsGuide])
        #expect(release?.items.last?.body.contains("**Siri**") == true)
    }

    @Test func italianFallbackDoesNotDependOnTheProcessLocale() {
        let fallback = FeatureDiscoveryManifest.fallback(for: "it")

        #expect(fallback.onboarding.title == "Scopri Personal Finance")
        #expect(fallback.releases.last?.title == "Più modi per gestire il tuo denaro")
    }

    @Test func stagedEnglishAndItalianManifestsDecodeThroughTheAppModel() throws {
        // The staged manifests are shipped into the test bundle as file references (see the
        // Xcode project's "Staged Remote Assets" group) so this reads the real files under
        // docs/remote-assets/feature-discovery, not a copy that could drift from them.
        var contentVersions: [String] = []
        var releaseIDs: [[String]] = []
        for filename in ["manifest", "manifest-it"] {
            let url = try #require(Bundle(for: BundleToken.self).url(forResource: filename, withExtension: "json"))
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(FeatureDiscoveryManifest.self, from: data)

            #expect(!manifest.contentVersion.isEmpty)
            #expect(!manifest.releases.isEmpty)
            contentVersions.append(manifest.contentVersion)
            releaseIDs.append(manifest.releases.map(\.id))
        }

        // English and Italian are meant to ship in lockstep — catch one being updated without the other.
        #expect(contentVersions[0] == contentVersions[1])
        #expect(releaseIDs[0] == releaseIDs[1])
    }

    @Test func italianGuideIncludesRegisteredSiriPhrases() {
        let copy = SiriWidgetsGuideCopy.localized(for: Locale(identifier: "it"))

        #expect(copy.siriPhrases == [
            "Aggiungi una transazione con Personal Finance",
            "Registra una spesa con Personal Finance",
        ])
        #expect(copy.widgets.map(\.title) == [
            "Impulso finanziario",
            "Scansiona uno scontrino",
            "Quanto puoi spendere",
        ])
        #expect(copy.widgets.map(\.availability) == [
            "Home: piccolo o medio · Blocco: circolare",
            "Home: piccolo · Blocco: circolare",
            "Home: piccolo",
        ])
        #expect(copy.privacyBullets.count == 3)
        #expect(copy.siriCompletion.contains("salva la transazione"))
    }

    private var fallbackContent: FeatureDiscoveryLoadedContent {
        FeatureDiscoveryLoadedContent(manifest: .fallback, mediaBaseURL: nil)
    }

    private var oldReleaseContent: FeatureDiscoveryLoadedContent {
        let fallback = FeatureDiscoveryManifest.fallback(for: "en")
        return FeatureDiscoveryLoadedContent(
            manifest: FeatureDiscoveryManifest(
                schemaVersion: fallback.schemaVersion,
                contentVersion: "old-live-manifest",
                onboarding: fallback.onboarding,
                releases: fallback.releases.filter { $0.id == "1.0-financial-pulse" }
            ),
            mediaBaseURL: nil
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FeatureDiscoveryCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class BundleToken {}
