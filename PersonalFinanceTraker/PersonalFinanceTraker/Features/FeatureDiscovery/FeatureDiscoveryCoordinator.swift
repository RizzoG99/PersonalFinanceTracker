import Foundation
import Observation

@MainActor
@Observable
final class FeatureDiscoveryCoordinator {
    private enum Key {
        static let hasCompletedTour = "feature_discovery_has_completed_tour"
        static let lastSeenReleaseVersion = "feature_discovery_last_seen_release_version"
        static let lastSeenReleaseID = "feature_discovery_last_seen_release_id"
    }

    private static let legacyVersionReleaseIDs = ["1.0": "1.0-financial-pulse"]

    var isShowingTour = false
    var releaseToPresent: FeatureDiscoveryManifest.Release?
    var pendingDestination: FeatureDiscoveryDestination?
    private(set) var manifest = FeatureDiscoveryManifest.fallback
    private(set) var mediaBaseURL: URL?
    private var presentedReleaseID: String?
    private var destinationAfterReleaseDismissal: FeatureDiscoveryDestination?

    private let defaults: UserDefaults
    private let service: FeatureDiscoveryService

    init(defaults: UserDefaults = .standard, service: FeatureDiscoveryService = FeatureDiscoveryService()) {
        self.defaults = defaults
        self.service = service
    }

    func loadAndPrepare(appVersion: String) async {
        let content = await service.load()
        prepare(content: content, appVersion: appVersion)
    }

    func prepare(content: FeatureDiscoveryLoadedContent, appVersion: String) {
        manifest = content.manifest
        mediaBaseURL = content.mediaBaseURL

        guard !isShowingTour, releaseToPresent == nil else { return }
        guard defaults.bool(forKey: Key.hasCompletedTour) else {
            isShowingTour = true
            return
        }
        presentUnseenRelease(for: appVersion)
    }

    func showTour() {
        isShowingTour = true
    }

    func finishTour(destination: FeatureDiscoveryDestination) {
        defaults.set(true, forKey: Key.hasCompletedTour)
        isShowingTour = false
        pendingDestination = destination
    }

    func dismissTour() {
        defaults.set(true, forKey: Key.hasCompletedTour)
        isShowingTour = false
    }

    func showWhatsNew(appVersion: String) {
        present(manifest.releases.last { $0.version == appVersion })
    }

    func dismissWhatsNew() {
        if let presentedReleaseID {
            defaults.set(presentedReleaseID, forKey: Key.lastSeenReleaseID)
        }
        releaseToPresent = nil
    }

    func performReleaseAction(destination: FeatureDiscoveryDestination?) {
        destinationAfterReleaseDismissal = destination
        dismissWhatsNew()
    }

    /// Completes routing only after the What's New sheet is fully gone. Presenting another
    /// sheet while its dismissal animation is still running is unreliable, especially for the
    /// receipt source chooser and the Activity list sheets.
    func completeWhatsNewDismissal() {
        dismissWhatsNew()
        presentedReleaseID = nil
        pendingDestination = destinationAfterReleaseDismissal
        destinationAfterReleaseDismissal = nil
    }

    func consumeDestination() -> FeatureDiscoveryDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    private func presentUnseenRelease(for appVersion: String) {
        guard let release = manifest.releases.last(where: { $0.version == appVersion }),
              migratedSeenReleaseID() != release.id else {
            return
        }
        present(release)
    }

    private func present(_ release: FeatureDiscoveryManifest.Release?) {
        releaseToPresent = release
        presentedReleaseID = release?.id
    }

    private func migratedSeenReleaseID() -> String? {
        if let releaseID = defaults.string(forKey: Key.lastSeenReleaseID) {
            return releaseID
        }
        guard let legacyVersion = defaults.string(forKey: Key.lastSeenReleaseVersion),
              let releaseID = Self.legacyVersionReleaseIDs[legacyVersion] else {
            return nil
        }
        defaults.set(releaseID, forKey: Key.lastSeenReleaseID)
        return releaseID
    }
}
