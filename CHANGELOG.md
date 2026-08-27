# Changelog

Plain-language, tester-facing notes — not a commit log. One bullet per
user-visible change, added under **Unreleased** before a PR opens (see
CLAUDE.md / AGENTS.md). `scripts/xcb release-notes` sends the Unreleased
section to TestFlight as "What to Test" and archives it under the build
number that shipped it.

## Unreleased
- iPad: Activity's filter chips and transaction table now resize to fit alongside the sidebar instead of being hidden behind it.
- iPad: shaking the device now hides amounts like it does on iPhone, and there's a new eye icon on iPad to hide/show amounts without shaking.
- Add Transaction: new "Scan receipt" button lets you fill amount, date, merchant, and category from a photo of a receipt (camera or your photo library). Everything is processed on your device and reviewed before saving — nothing is filled in without you seeing it first, and low-confidence values are marked so you know to double-check them.

## 76 — 2026-08-27
- Fixed keyboard focus jumping in the Add/Edit Transaction and Goal sheets.
