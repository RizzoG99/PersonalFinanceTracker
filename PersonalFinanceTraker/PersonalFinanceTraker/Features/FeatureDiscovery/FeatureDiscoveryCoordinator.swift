import Foundation
import Observation

@MainActor
@Observable
final class FeatureDiscoveryCoordinator {
    private enum Key {
        static let hasCompletedTour = "feature_discovery_has_completed_tour"
        static let lastSeenReleaseVersion = "feature_discovery_last_seen_release_version"
    }

    var isShowingTour = false
    var releaseToPresent: FeatureDiscoveryManifest.Release?
    var pendingDestination: FeatureDiscoveryDestination?
    private(set) var manifest = FeatureDiscoveryManifest.fallback
    private(set) var mediaBaseURL: URL?

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
        releaseToPresent = manifest.releases.last { $0.version == appVersion }
    }

    func dismissWhatsNew() {
        if let releaseToPresent {
            defaults.set(releaseToPresent.version, forKey: Key.lastSeenReleaseVersion)
        }
        releaseToPresent = nil
    }

    func performReleaseAction(destination: FeatureDiscoveryDestination?) {
        dismissWhatsNew()
        pendingDestination = destination
    }

    func consumeDestination() -> FeatureDiscoveryDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    private func presentUnseenRelease(for appVersion: String) {
        guard let release = manifest.releases.last(where: { $0.version == appVersion }),
              defaults.string(forKey: Key.lastSeenReleaseVersion) != release.version else {
            return
        }
        releaseToPresent = release
    }
}
