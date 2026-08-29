# Changelog

Plain-language, tester-facing notes — not a commit log. One bullet per
user-visible change, added under **Unreleased** before a PR opens (see
CLAUDE.md / AGENTS.md). `scripts/xcb release-notes` sends the Unreleased
section to TestFlight as "What to Test" and archives it under the build
number that shipped it.

## Unreleased
- Fixed a brief screen flash/flicker right when Face ID kicks in on unlock.
- Removed the privacy screen that used to cover the app while screen recording; the app switcher snapshot cover is unaffected.

## 81 — 2026-08-29
- Scan receipt: either volume button now takes the shot, like in the Camera app, so you can hold the phone steady over the receipt instead of reaching for the on-screen shutter.
- Italian now covers Settings discovery and Analysis labels, and the Settings close button immediately follows a theme change.

## 80 — 2026-08-29
- New "Scan Receipt" home-screen widget (small, plus a Lock Screen circular one): tapping it opens the app straight into the receipt camera — no menu, no choosing between photo and camera.
- Scan receipt: the photo is now trimmed to the receipt the camera outlined, so a second receipt lying on the same table can no longer contribute its total. Previously a €5 receipt could come back with the amount of the one next to it, or ask you to choose between the two.
- Scan receipt: when the category could not be worked out from the receipt, the scan now says "Guessed the category — check it" instead of reporting it as filled in. The category is a required field so something is always chosen, but a guess no longer looks like a reading.
- Scan receipt: the camera now outlines the receipt on screen as it finds it, and the caption changes to "Receipt detected", so you can tell it is framed before you tap. It is guidance only — the shutter always works, whether or not an outline is showing.
- Scan receipt: new **Settings > Categories > Scan Categories** screen. Pair each kind of receipt (eating out, groceries, fuel, pharmacy…) with one of your own categories, once, and scans use it from then on. This matters if you renamed a category or created your own: until now the scan had to guess the category from its *name*, so a category called something the app didn't recognise was never picked. Anything you leave on "Automatic" keeps working exactly as before.
- Scan receipt: many more kinds of shop are now recognised from Apple Maps — cinemas, gyms, hotels, parking, car repair, museums, schools, pet services and more. Previously only nine kinds were, and an unrecognised one fell back to whichever category you use most.
- Scan receipt: ice cream shops, patisseries and similar are now recognised as eating out. Previously a gelateria matched none of the known merchant types and the scan fell back to whichever category you use most, which could be something as unrelated as bank fees.
- Scan receipt: fixed a scan filling in the amount, date and shop name but leaving the category empty. The category was being chosen before the category list had finished loading, so it had nothing to choose from.
- Scan receipt: fixed a receipt whose total is printed twice in a row (for example "TOT. COMPLESSIVO" above two identical amounts) being reported as unreadable, with no amount filled in at all.
- Scan receipt: the shop name, date and category are now read correctly when the receipt is photographed from further back or lying at an angle, instead of the name coming out as part of the total line.
- Scan receipt: taking a photo is now one tap. The camera opens straight into a viewfinder with a shutter button, instead of waiting to find the receipt's edges, asking you to adjust the corners, and then offering more pages and a review screen before it read anything.
- Scan receipt: added a light you can switch on in the camera, which stays on for framing rather than firing at the moment of the shot. Your choice is remembered for next time.
- Scan receipt: receipts photographed in poor light are read noticeably better. Each photo is now read twice — once as shot and once with contrast boosted — and whichever the camera is more confident about is used. On a dim receipt this was the difference between the shop name coming out as "Lucumento Commerctale" and as "Cremeria", and between the year reading 2021 and 2026.

## 79 — 2026-08-29
- Scan receipt: fixed a scan occasionally filling in the wrong amount — on some receipts the first item's price was picked instead of the total, with no warning that it was a guess.
- Scan receipt: receipts whose total line the camera misreads (for example "TOTALE COHPLESSIVO") are now still read correctly, because the amount is confirmed against the rest of the receipt instead of relying on that one line.
- Scan receipt: the shop name is picked more reliably — VAT lines, addresses, column headings and till serial numbers are no longer mistaken for it, including on receipts photographed sideways.
- Scan receipt: English-language receipts are now recognised, including "Total", "Grand Total" and "Amount Due" wording, US month-first dates, and amounts written as 1,234.56. Sub-totals, tax, cash given and suggested tips are correctly ignored.
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
