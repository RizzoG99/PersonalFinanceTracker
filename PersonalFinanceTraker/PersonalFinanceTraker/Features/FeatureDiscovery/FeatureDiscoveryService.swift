import Foundation

struct FeatureDiscoveryLoadedContent: Sendable {
    let manifest: FeatureDiscoveryManifest
    let mediaBaseURL: URL?
}

actor FeatureDiscoveryService {
    private let manifestURL: URL?
    private let session: URLSession

    init(manifestURL: URL? = FeatureDiscoveryConfiguration.manifestURL, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.session = session
    }

    func load() async -> FeatureDiscoveryLoadedContent {
        guard let manifestURL else {
            return FeatureDiscoveryLoadedContent(manifest: .fallback, mediaBaseURL: nil)
        }

        let languageCode = Locale.current.language.languageCode?.identifier
        let localizedURL = languageCode.map {
            manifestURL.deletingLastPathComponent().appending(path: "manifest-\($0).json")
        }

        for url in [localizedURL, manifestURL].compactMap(\.self) {
            if let content = await loadManifest(from: url) {
                if url == manifestURL {
                    return FeatureDiscoveryLoadedContent(
                        manifest: content.manifest.applyingBuiltInCopy(for: languageCode),
                        mediaBaseURL: content.mediaBaseURL
                    )
                }
                return content
            }
        }

        return FeatureDiscoveryLoadedContent(manifest: .fallback, mediaBaseURL: nil)
    }

    private func loadManifest(from manifestURL: URL) async -> FeatureDiscoveryLoadedContent? {
        do {
            var request = URLRequest(url: manifestURL)
            // Release content is managed remotely. Avoid presenting a previous
            // manifest after an editor has published a new What’s New entry.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
                return nil
            }
            let manifest = try JSONDecoder().decode(FeatureDiscoveryManifest.self, from: data)
            guard manifest.schemaVersion == 1 else {
                return nil
            }
            return FeatureDiscoveryLoadedContent(
                manifest: manifest,
                mediaBaseURL: manifestURL.deletingLastPathComponent()
            )
        } catch {
            return nil
        }
    }
}

private enum FeatureDiscoveryConfiguration {
    static var manifestURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "FeatureDiscoveryManifestURL") as? String,
              let url = URL(string: rawValue),
              url.scheme == "https" else {
            return nil
        }
        return url
    }
}
