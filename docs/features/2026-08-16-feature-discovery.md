# Feature: Remote Feature Discovery

## Problem
New users need a clear, optional introduction to Personal Finance Tracker, while returning users need a lightweight way to discover meaningful features without increasing the app download size for tutorial media.

## Approach
Build two related experiences: a first-launch **Explore the app** tour and a version-triggered **What's New** sheet. Both are driven by a remote, versioned content manifest served from a Cloudflare R2 bucket through a custom asset domain. The app ships only the SwiftUI layout, copy fallback, SF Symbols, and accessibility labels; remote images and short silent motion previews progressively enhance the experience when available.

Use still images for the general overview and reserve an auto-muted, looping 4–8 second preview for complex visual interactions such as adding a widget. R2 with a custom domain is the first hosting choice because the media is public, non-sensitive, small in volume, and does not need video-platform features such as transcoding or viewer analytics.

## Key decisions
- Store public instructional assets only; never upload customer transactions, account details, or app screenshots containing real financial data.
- Use a custom domain such as `assets.<product-domain>` rather than Cloudflare's `r2.dev` development URL.
- Publish an HTTPS JSON manifest at a stable URL, for example `https://assets.<product-domain>/feature-discovery/manifest.json`. The manifest defines release version, cards, copy, alt text, media URL, media type, and optional app destination.
- Version every immutable asset in its file name (for example, `widget-preview-v1.mp4`) and serve it with long-lived cache headers. Update the small manifest to reference new assets instead of overwriting them.
- Treat remote media as optional: retain a native visual fallback and meaningful copy if the network is unavailable, an asset fails to decode, or the manifest cannot be loaded.
- Keep previews silent, pause them when off-screen or when Reduce Motion is enabled, and provide a static poster image plus descriptive accessibility text.
- Start with a maximum of one motion preview and four onboarding cards. Revisit a dedicated video provider only if adaptive bitrate streaming, captions, detailed playback analytics, or a substantial media catalogue becomes necessary.
- Persist `hasCompletedFeatureTour` and `lastSeenWhatsNewVersion` locally; media/content state does not require a SwiftData migration.

## Architecture notes
- Create `PersonalFinanceTraker/PersonalFinanceTraker/Features/FeatureDiscovery/FeatureDiscoveryContent.swift` for codable manifest/card models, curated native fallback content, and validation.
- Create `PersonalFinanceTraker/PersonalFinanceTraker/Features/FeatureDiscovery/FeatureDiscoveryService.swift` for manifest retrieval, cache policy, and graceful failure handling.
- Create `PersonalFinanceTraker/PersonalFinanceTraker/Features/FeatureDiscovery/FeatureDiscoveryCoordinator.swift` for first-launch and release-notes eligibility plus destination routing.
- Create `PersonalFinanceTraker/PersonalFinanceTraker/Features/FeatureDiscovery/FeatureDiscoveryView.swift` for the paged onboarding and What's New presentation.
- Modify `PersonalFinanceTraker/PersonalFinanceTraker/App/AuthenticationWrapper.swift` to evaluate eligibility only after successful authentication.
- Modify `PersonalFinanceTraker/PersonalFinanceTraker/Features/MainTabView/MainTabView.swift` to perform discovery navigation actions using its existing selected-tab state.
- Modify `PersonalFinanceTraker/PersonalFinanceTraker/Features/Profile/Views/ProfileView.swift` (or a focused Profile component) to add manual **Explore the app** and **What's New** entry points.
- Add tests for manifest decoding, fallback behavior, version eligibility, navigation mapping, and accessibility / Reduce Motion behavior where testable.
- Provision outside the iOS repository: Cloudflare R2 bucket, custom-domain DNS mapping, cache rule for immutable media, deployment credentials scoped to that bucket, and a small, documented asset-publishing workflow.
- No SwiftData schema changes.

## Where to start
Set up the Cloudflare R2 custom domain and publish a single manifest plus one static placeholder image, then agree the manifest contract before building the SwiftUI client.
