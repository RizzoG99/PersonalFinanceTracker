# Feature Discovery Remote Assets

This directory is an upload staging area, not an Xcode asset catalog. Nothing here is part of the iOS app target.

## Upload layout

Upload the contents of this folder to the `feature-discovery/` prefix of the production R2 bucket:

```text
feature-discovery/
  manifest.json
  manifest-it.json
  onboarding/
    overview-v1.png
    activity-v1.png
    budgets-v1.png
    insights-v1.png
  releases/
    financial-pulse-v1.png
    safe-to-spend-v1.png
    travels-v1.png
    scan-receipt-v1.png
    recurring-transactions-v1.png
    siri-widgets-v1.png
```

The app first loads `manifest-<language-code>.json` when one exists (for example `manifest-it.json`), then falls back to `manifest.json`. Media paths are relative to the manifest at `https://assets.finance.gabrielerizzo.dev/feature-discovery/`.

## Production URL

Upload this directory's contents to the `pft-public-assets-prod` bucket under `feature-discovery/`. The app configuration requests the custom domain, which requires TLS 1.2 or newer:

```text
https://assets.finance.gabrielerizzo.dev/feature-discovery/manifest.json
```

The endpoint already contains the previously published feature-discovery release. Upload the refreshed manifests and all newly referenced artwork before releasing an app build that includes this fallback, so remote and bundled content stay aligned. Do not restore or ship the former `r2.dev` URL.

## Publishing rules

- Do not overwrite a published media file. Publish a new, versioned filename and update `manifest.json` instead.
- Give versioned media a long immutable cache lifetime. Keep `manifest.json` short-lived or revalidating.
- Only publish fictional, public instructional content. Never upload a screenshot or video containing a real customer’s data.
- Keep images text-free; the app supplies accessible, localised copy and VoiceOver descriptions.
- Add a silent 4–8 second MP4 plus a static poster image only for interactions that need motion to explain them, such as a widget setup flow.
