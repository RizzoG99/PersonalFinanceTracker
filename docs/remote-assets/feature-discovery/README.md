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
```

The app first loads `manifest-<language-code>.json` when one exists (for example `manifest-it.json`), then falls back to `manifest.json`. Media paths are relative to the manifest, so moving from staging to `https://assets.<your-domain>/feature-discovery/` does not require changing the JSON.

## Development URL

Until a product domain is available, upload this directory's contents to the `pft-public-assets-prod` bucket under `feature-discovery/`. The development app configuration currently requests:

```text
https://pub-acab7f749262455f81f509d6c0f66518.r2.dev/feature-discovery/manifest.json
```

The endpoint currently returns `404`, which is expected until `manifest.json` and the `onboarding/` directory have been uploaded. Before release, replace `FeatureDiscoveryManifestURL` in the app target's Info settings with the production custom-domain URL; do not ship an `r2.dev` URL.

## Publishing rules

- Do not overwrite a published media file. Publish a new, versioned filename and update `manifest.json` instead.
- Give versioned media a long immutable cache lifetime. Keep `manifest.json` short-lived or revalidating.
- Only publish fictional, public instructional content. Never upload a screenshot or video containing a real customer’s data.
- Keep images text-free; the app supplies accessible, localised copy and VoiceOver descriptions.
- Add a silent 4–8 second MP4 plus a static poster image only for interactions that need motion to explain them, such as a widget setup flow.
