# Install the TEST app alongside Personal Finance

Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` in this checkout and select the shared **PersonalFinanceTraker-TEST** scheme. Choose your iPhone and Run. Xcode uses the existing development team and automatic signing; on the first device build it may need to register the new app identifiers, App Group and iCloud container with your Apple developer account.

The Home Screen name is **PFT TEST**, keeping the TEST label visible without a long app name. It starts with its own empty store and preferences. The original installation is not replaced or migrated.

| Identity | Normal app | TEST app |
| --- | --- | --- |
| App bundle ID | `rizzoG99.PersonalFinanceTraker` | `rizzoG99.PersonalFinanceTraker.test` |
| Habit/receipt widget ID | `rizzoG99.PersonalFinanceTraker.widget` | `rizzoG99.PersonalFinanceTraker.test.widget` |
| Safe to Spend widget ID | `rizzoG99.PersonalFinanceTraker.SafeToSpendWidget` | `rizzoG99.PersonalFinanceTraker.test.SafeToSpendWidget` |
| App Group | `group.rizzoG99.PersonalFinanceTraker` | `group.rizzoG99.PersonalFinanceTraker.test` |
| iCloud backup container | `iCloud.rizzoG99.PersonalFinanceTraker` | `iCloud.rizzoG99.PersonalFinanceTraker.test` |
| Widget URL scheme | `personalfinancetraker` | `personalfinancetraker-test` |

SwiftData's automatic group container, widget snapshots/pending actions, sandbox preferences, and the default Keychain access group follow the separate installation identity. TEST widgets use only the TEST group and URL scheme. There is no shared Keychain entitlement. Production Debug/Release identifiers and entitlements are unchanged.

## Debugging and profiling

- Run and Test use **Debug-TEST**.
- Product → Profile and Archive use **Release-TEST**, with Release optimization and debug symbols.
- Both TEST configurations define `PFT_TEST_BUILD`, including both widget extensions.
- All diagnostic launch arguments are **disabled by default**, including the recorder, onboarding/tip overrides, data seeding and receipt-photo export. Test actions do not inherit app launch arguments.
- Enable `-performanceAudit` and `-performanceAuditScenario activity-search-5k-test` only for a recording. Optional tip/tour overrides are listed separately in the scheme. Profile inherits Run's arguments.

### Load the disposable 5,000-transaction fixture

In Edit Scheme → Run → Arguments, enable **`-seedPerformanceAuditData 5000`** for one launch, then disable it before normal testing or recording. Profile inherits Run's arguments; check that the seed argument is disabled before a measurement.

This flag replaces the TEST ledger's transactions/categories/goals/travels/recurrence data on **every launch while enabled**. It sets the TEST PIN to **1234** and disables biometrics. TEST seeding works on a physical device and in Release-TEST. In the normal app, seeding remains compiled only for Debug simulator builds. No production device build gains this capability.

For a search capture: after seeding once and disabling the seed flag, enable the recorder/scenario arguments above, choose Product → Profile, unlock the TEST app, wait for launch activity to settle, then record Time Profiler + Points of Interest. Distinguish keyboard opening, typing, the 250 ms debounce, computation and publication. Save the trace and note its run number, then disable the recording arguments. The Debug-only skip-lock argument is not enabled in this scheme and does not apply to Release-TEST.

`-performanceAuditReceiptFixtures` explicitly saves local receipt photos and metadata for a diagnostic replay. Leave it disabled for ordinary testing; those files and raw traces remain local and ignored by Git.

### CLI

```sh
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb build
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb build -configuration Release-TEST
rtk proxy env PFT_XCODE_SCHEME=PersonalFinanceTraker-TEST scripts/xcb test -only-testing:PersonalFinanceTrakerTests/AppIdentityTests
```

Omit `PFT_XCODE_SCHEME` to use the original scheme. Both schemes use the simulator resolved by `scripts/xcb which-sim`; distinct bundle IDs allow both apps to coexist there as well. No app installation or deletion is performed by selecting a scheme.

## Publication verification — 2026-10-16

The publication candidate is based on PR #230 review corrections at `8dbb9e4`,
with the TEST contribution and Activity baseline harness. Fresh checks use
`.worktrees/pr230-test-variant-verification` and its dedicated iPhone 17 Simulator,
iOS 27.0 (`24A434`), arm64. The personal device and the original profiling
simulator/store are not used.

- Complete standard unit target: **827 passed, 0 failed, 15 explicit skips**;
  897 passing executions including parameterized cases. Both identity/store-location
  checks execute. The 15 skips include the opt-in Activity baseline, exercised separately.
- TEST identity/store-location, pending-intent, snapshot and search suites:
  **23 passed, 0 failed, 0 skipped**.
- Release-TEST built; the build activity log confirms `-O`. The app and both
  widgets have TEST bundle IDs and generated **Simulator** App Group entitlements;
  the app has the TEST iCloud identifier, URL scheme and `PFT TEST` display name.
  These are not physical-device signing/provisioning checks.
- On the disposable simulator, Release-TEST seeded exactly **5,000 transactions**
  and retained them after relaunch without the seed argument. TEST data/App Group
  roots differ from the normal app's roots; all four normal-app store/WAL files
  retained their SHA-256 hashes. The smoke did not install or launch the normal app.
- Both shared schemes have no enabled diagnostic arguments. All 12 existing
  project/target Debug and Release configuration objects match the review base.
  TEST plists/entitlements and the project plist are valid.

Evidence is retained locally under `.build/pr230-two-commits/` in the performance
worktree and the verification checkout's `.build/`. These checks verify build/data
identity and behavior; they are not a new physical-device performance comparison.
Historical results below retain their original source and scope.

## Historical verification — 2026-10-15

Validated in `.worktrees/performance-baselines`, based on `d1b7f5b`, on the worktree's iPhone 17 simulator / iOS 27.0:

- Debug-TEST built; 23 selected identity, store-location, pending-intent, search and snapshot tests passed, zero failures/skips.
- Release-TEST built successfully. Its app and both embedded widget bundle IDs and generated App Group/iCloud entitlements were checked for the `.test` identity.
- The original scheme built; 15 selected identity, store-location, pending-intent and snapshot tests passed, zero failures/skips.
- Both bundle IDs coexist. The Release-TEST app launched, seeded exactly 5,000 transactions, and retained them after relaunch without the seed argument. App sandboxes and App Group directories are distinct. SHA-256 hashes of all four normal-app store/WAL files remained identical across those TEST launches. The smoke procedure did not install or launch the normal app.
- The existing project's Debug/Release configuration objects and original shared scheme were preserved; all unrelated pre-existing dirty files retained their captured hashes. `git diff --check` and Graphify update passed; Graphify changed no Git status.

Local evidence: `.build/test-variant-{debug,production}-summary.json`, `.build/test-variant-release.log`, and `.build/test-variant-smoke-summary.json`. There are existing receipt-camera concurrency warnings in the builds. No search optimization or performance improvement is claimed by these identity changes.

Physical-device signing/install, iCloud backup access and widget taps still need device verification. View layouts/styles were not changed; light/dark, compact/wide, accessibility Dynamic Type and VoiceOver were not exercised in this configuration task.
