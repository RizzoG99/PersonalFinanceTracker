import Foundation

struct FeatureDiscoveryManifest: Codable, Sendable {
    struct Onboarding: Codable, Sendable {
        let id: String
        let title: String
        let pages: [Page]
    }

    struct Page: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let body: String
        let symbolName: String
        let media: Media?
        let destination: FeatureDiscoveryDestination
    }

    struct Release: Codable, Identifiable, Sendable {
        let id: String
        let version: String
        let title: String
        let summary: String
        let items: [ReleaseItem]
    }

    struct ReleaseItem: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let body: String
        let symbolName: String
        let media: Media?
        let destination: FeatureDiscoveryDestination?
        let actionTitle: String?
    }

    struct Media: Codable, Sendable {
        let kind: Kind
        let path: String
        let accessibilityLabel: String

        enum Kind: String, Codable, Sendable {
            case image
            case video
        }

        func url(relativeTo baseURL: URL?) -> URL? {
            guard let baseURL else { return nil }
            return baseURL.appending(path: path)
        }
    }

    let schemaVersion: Int
    let contentVersion: String
    let onboarding: Onboarding
    let releases: [Release]
}
