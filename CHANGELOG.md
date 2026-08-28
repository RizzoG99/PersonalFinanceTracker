# Changelog

Plain-language, tester-facing notes — not a commit log. One bullet per
user-visible change, added under **Unreleased** before a PR opens (see
CLAUDE.md / AGENTS.md). `scripts/xcb release-notes` sends the Unreleased
section to TestFlight as "What to Test" and archives it under the build
number that shipped it.

## Unreleased
- Scan receipt: fixed the very first scan started from Home/Activity/Insights opening an empty Add Transaction form — the scanned values were dropped on that first attempt and only appeared if you scanned again.
- Scan receipt: recognition now reads the receipt's layout rather than a flat list of lines, so amounts printed in a separate column from their labels are matched up reliably instead of by guesswork.
- Scan receipt: the amount is now taken from the receipt's official "TOTALE COMPLESSIVO" line when it's printed, instead of asking you to pick between it and another total line whenever one of them was misread.
- Scan receipt: amounts and dates printed in unusual formats are now also read, rescuing receipts where the amount previously came back blank.
- Scan receipt: the merchant is now picked as the largest text on the receipt rather than the topmost line, so headers like "SCONTRINO FISCALE" printed above the shop name are no longer mistaken for it.
- Scan receipt: fixed a shop whose name merely contains "reso" (e.g. a resort) being treated as a refund.

## 78 — 2026-08-28
- Scan receipt: fixed two-column thermal receipts (label and price printed far apart, e.g. bar/restaurant slips) leaving the amount blank and picking the wrong category.
- Scan receipt: fixed the amount not filling in when the Amount field's keyboard was still open (it's focused automatically when Add Transaction opens) at the moment a scan finished.
- Add Transaction: the first time you open this screen, a tooltip now points out the new "Scan receipt" button.
- Scan receipt: if camera access was previously denied, tapping "Take Photo" now shows a clear alert with a Settings link instead of a cryptic error after the fact.
- Scan receipt: capture/recognition failures now always show the plain "couldn't read this receipt" message instead of a raw technical error code.
- Scan receipt: replaced the repeated "Scanned — check before saving" note under every filled-in field with a single dismissible banner at the top of the form.
- Scan receipt: fixed another split-column layout where the amount was missed (the label and price columns came back as two whole separate blocks rather than one line apart).
- Scan receipt: category guessing now also checks Apple Maps for the merchant's business type (using the address printed on the receipt, not your location) when its name alone doesn't give it away — e.g. a restaurant with no obvious food word in its name.
- Scan receipt: fixed sideways/rotated photos (e.g. picked from your library in landscape) reading as unreadable — they're now straightened before recognition, same as an upright photo.
- Added a "Scan receipt" shortcut next to "+ Add" (iPhone nav bar and iPad sidebar) that jumps straight to the camera/photo-library choice, scans, and opens Add Transaction already filled in — one tap instead of opening Add Transaction first.

## 77 — 2026-08-28
- iPad: Activity's filter chips and transaction table now resize to fit alongside the sidebar instead of being hidden behind it.
- iPad: shaking the device now hides amounts like it does on iPhone, and there's a new eye icon on iPad to hide/show amounts without shaking.
- Add Transaction: new "Scan receipt" button lets you fill amount, date, merchant, and category from a photo of a receipt (camera or your photo library). Everything is processed on your device and reviewed before saving — nothing is filled in without you seeing it first, and low-confidence values are marked so you know to double-check them.

## 76 — 2026-08-27
- Fixed keyboard focus jumping in the Add/Edit Transaction and Goal sheets.
