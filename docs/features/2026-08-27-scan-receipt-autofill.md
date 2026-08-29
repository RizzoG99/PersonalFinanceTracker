# Feature: Scan a receipt to auto-fill a transaction

## Decision summary

Ship issue #59 as a validation build: a camera/photo scan action inside Add
Transaction that pre-fills amount, date, merchant, and category, with no image
storage and no deferred-review inbox. The feature's value rests on one unproven
assumption — that on-device OCR can reliably read the total off a real receipt —
so v1 is scoped to test that as cheaply as possible before any bigger design
(flagged transactions, a receipt inbox) is built on top. Category is inferred
and always filled, even when wrong, because it's a required field and the plan
is to let the user's corrections make future inference better.

## Prior art

Checked before writing any parsing code:

- **[tinvois-parser](https://github.com/rekloud/tinvois-parser)** — keyword-tags
  lines ("SUM"/"NETTO"/"BRUTTO"/"VAT") for totals rather than ML; date is "first
  regex match"; merchant is a known-merchant list, else first line. Confirms the
  heuristics below aren't an underbuilt shortcut — they're the standard approach.
- **[andreichenchik/receipt](https://github.com/andreichenchik/receipt)** —
  Vision + geometric heuristics on iOS, no ML. Confirms the platform choice.
- **ShawnBaek's Vision tutorial** (relayed by the user) — confirmed
  `VNRecognizeTextRequest` supports `it-IT` at `.accurate`/revision 2. Decision:
  pin `recognitionLanguages: ["it-IT"]` explicitly rather than auto-detecting.
  Also demoed `NaturalLanguage`/`NLTagger` lexical tagging — not adopted, our
  keyword list is more precise for less code.
- **[alfianlosari/AIReceiptScanner](https://github.com/alfianlosari/AIReceiptScanner)** —
  sends the photo to GPT-4o, cloud-only. Considered and rejected: conflicts with
  the issue's "process locally where practical" and this feature's privacy
  stance. On-device Vision + heuristics stays the approach.
- **[clovaai/cord](https://github.com/clovaai/cord)** — a labeled receipt
  dataset, kept in reserve as extra parser fixtures if the user's own receipts
  (6 on hand, more arriving this week) prove too thin.
- No project reviewed learns from the user's own corrections — the
  merchant→category memory below is original to this feature.

## Problem and outcome

Expenses go unrecorded not because logging is slow (typing an amount and
tapping a category chip takes ~5 seconds) but because it never happens — the
receipt goes in a pocket and is forgotten. The outcome: capturing an expense
from its receipt should be at least as fast and no less trustworthy than typing
it, and get better at guessing as the user corrects it.

## User experience

**Entry point:** a camera button in the Add Transaction nav bar, beside the
existing Repeat toggle. Add mode only; hidden for Transfer.

**Flow:**
1. Tap camera → **Take Photo** / **Choose Photo**.
2. Camera → VisionKit document scanner (auto edge detect/crop). Library →
   `PhotosPicker`.
3. On-device Vision recognition (`recognitionLanguages: ["it-IT"]`, `.accurate`)
   → `ReceiptParser` extracts total, date, merchant, refund flag.
4. Category inferred (learned mapping → keyword table → most-used fallback).
5. Sheet dismisses onto the populated form; keyboard stays closed so the user
   inspects rather than types over values (existing `shouldAutoFocusAmount`
   behavior).
6. A status line states what happened, including any date fallback.
7. User reviews (including the guessed category), saves as normal. If the scan
   originated this transaction, the merchant→category pairing is recorded for
   next time.

## Key states and edge cases

- **Ambiguous total** (e.g. `CONTANTI` cash-tendered line outranking `TOTALE`):
  a single keyword match (`TOTALE`/`TOT.`/`IMPORTO`) is used silently; multiple
  or zero matches surface inline candidate chips under the Amount row instead of
  guessing.
- **Scanned-value marking:** fields the scan wrote (including the guessed
  category) carry a marker until edited or tapped, so review is structural, not
  just a hope.
- **Rescan:** replaces scan-sourced values only; hand-typed values are never
  touched.
- **Bad/out-of-range date:** clamped to today, stated in the status line, and
  not marked as scanned (it wasn't).
- **Refund receipts** (`RESO`/`RIMBORSO`/`STORNO`): flips type to Income, but
  only if no category is selected yet — `TransactionFormView` clears category on
  type change, so flipping under a chosen category would silently wipe it.
- **Category inference, three tiers, cheapest first:**
  1. Learned mapping (`MerchantCategoryMapping`, merchant → categoryId),
     recorded only when a **scan-originated** transaction is saved — typed
     names are too inconsistent to learn from.
  2. Static keyword table (supermarket chains, `farmacia`, fuel brands, …)
     fuzzy-matched against the user's own category names/emojis.
  3. Most-used category for the transaction type (`categoryUsage`, already
     computed) as a last resort, so the required field is never left empty.
- **Nothing readable:** alert, form untouched.
- **Camera permission denied:** alert with Settings link (first camera
  permission this app has ever asked for).
- **Cancelled capture:** no-op.
- **Multi-page receipt:** pages concatenated before parsing.
- **Foreign currency:** ignored; base currency kept.

## MVP

- Nav-bar scan action, Add mode only.
- Camera (document scanner) + photo library capture.
- On-device text recognition (`it-IT`, `.accurate`); image discarded
  immediately, never persisted.
- `ReceiptParser`: total (with candidate fallback), date (sanity-clamped),
  merchant (lightly cleaned), refund detection.
- Category inference: learned mapping → keyword fallback → most-used default,
  backed by a new `MerchantCategoryMapping` SwiftData model.
- Fill-only-defaults policy with scanned-value marking (including category) and
  a status line.
- Parser and category-inference unit tests against real receipt fixtures.

## Non-goals

- Storing/displaying the receipt image.
- Line-item extraction or splitting a receipt into multiple transactions.
- Scanning from Edit mode.
- Deferred review (`needsReview` flag on transactions, or a receipt inbox) —
  explicitly deferred pending v1's OCR accuracy results.
- Currency detection/conversion.
- Cloud or server-side OCR (considered via AIReceiptScanner, rejected).

## Product decisions

- **Discard the image, don't store it** — no schema change beyond the mapping
  model, no storage growth, an honestly minimal permission string.
- **Add mode only** — the natural moment; Edit-mode overwrite semantics get
  murky once every field is already populated.
- **Category always inferred and filled, even wrong** — the field is required;
  a wrong-but-filled guess the user corrects beats a blocked Save button, and
  the correction is exactly the training signal the learned tier needs.
- **Fill-only-defaults, not a confirm dialog** — satisfies "never overwrite
  user input" with an `if` on each field, not a modal.

## Technical considerations

- `EditAddTransactionViewModel` already accepts a `TransactionDraft` and
  pre-fills from it (widget review flow uses the same path), including
  suppressing the keyboard so the user reviews before typing further — a scan is
  a second producer of the same draft.
  (`Features/EditAddTransactionView/EditAddTransactionViewModel.swift`)
- `TransactionFormView`'s `.onChange(of: transactionType)` clears
  `selectedCategory`/`selectedGoal` — governs the refund-type-flip gate above.
- No camera/photo code or `NSCameraUsageDescription` exists anywhere in the app
  target today; this is genuinely new permission surface.
- `ReceiptParser` is pure Swift (no SwiftUI/SwiftData), unit testable against
  fixture text before any UI is built.
- Recognition via `VNRecognizeTextRequest`, pinned to `recognitionLanguages:
  ["it-IT"]` at `.accurate` (confirmed supported). Check whether iOS 26's
  `RecognizeDocumentsRequest` gives better line structure for free (deployment
  target is iOS 26.0).
- New `MerchantCategoryMapping` SwiftData model (merchant `String`,
  `categoryPersistentId`) — the only schema addition; no migration needed
  (project isn't on the App Store yet).
- Privacy copy: on-device only, image discarded after parsing, nothing kept.

## Success signals

On real receipts, total-extraction accuracy — target ≥80%, provisional on the
6 fixtures currently on hand (more arriving through the week). Below target,
the feature isn't worth the camera permission and should be cut, not patched.
Category-inference accuracy has no target yet (tier 3 guarantees a fill either
way) — tracked by feel until there's real usage.

## Open questions

- Is the cleaned merchant string usable as a transaction name, or still noisy
  enough to drop from v1?
- If OCR proves out, which deferred-capture direction follows: flagged
  transactions in Activity, or a dedicated receipt inbox?

## Where to start

Run Vision over the 6 receipts on hand, dump recognized lines to fixtures, and
write `ReceiptParser` (total + date + merchant + refund flag) against them —
before any camera permission, plist change, or SwiftUI work. Add fixtures as
more receipts arrive. Category inference (`MerchantCategoryMapping` + keyword
table + usage fallback) can be built and unit-tested alongside the parser,
fully independent of the camera/UI work.
