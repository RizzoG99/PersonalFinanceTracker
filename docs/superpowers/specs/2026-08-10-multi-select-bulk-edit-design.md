# Multi-select + bulk edit in the Activity list — design

**Status:** approved, ready for implementation plan.
**Date:** 2026-08-10.

## Problem

The Activity list can only act on one transaction at a time. Fixing a batch
of mis-categorized rows, deleting a run of test entries, or renaming several
imports means repeating swipe/edit once per row. The view model already
carries the breadcrumb for this gap:

> "Multi-item deletion has no UI entry point today (no multi-select mode)."
> (`TransactionListViewModel.scheduleDeletionOrPromptRecurrence`)

## Goal

A selection mode in the Activity list that lets the user pick several
transactions and act on them together: **delete, change category, change
amount, edit description** — each fully reversible via the existing undo
banner.

## Product decisions (settled during brainstorming)

- **Action set:** all four — delete, change category, change amount, edit
  description. "Change amount" sets every selected row to one identical
  value (kept at the user's request; the confirm/apply UX makes the
  overwrite obvious).
- **Entry:** **long-press** any row enters selection mode with that row
  pre-selected — the iOS-native gesture (Photos/Files/Mail). No permanent
  toolbar chrome when not selecting.
- **Edit safety:** category/amount/description edits **apply immediately,
  then show the 5s undo banner** — same machinery as delete. Fully
  reversible by restoring each row's prior values.
- **Recurring rows in bulk:** bulk operates on the **selected occurrences
  only** — no "this only / this & future" prompt. This matches the existing
  multi-delete path, which already skips the recurrence prompt (it fires
  only for a single swiped row). Bulk-deleting occurrences does **not**
  close their recurrence rule; future occurrences keep generating.
  Predictable beats clever in bulk.
- **Recurring rows under bulk _edit_:** bulk edit inherits single-edit
  semantics exactly. `TransactionActor.update` (`TransactionActor.swift:72`)
  writes only timestamp/amount/note/category/currency/goal/categoryModel —
  it **never touches recurrence linkage**. So editing a recurring
  occurrence's category/amount/note diverges that one occurrence's value in
  place; its rule link is untouched and future occurrences keep generating
  unchanged. Undo is lossless (the link never moved). No divergence /
  detach logic to add — bulk just loops the same `update`.
- **Select All scope:** selects only the **currently visible** (searched /
  filtered) rows, never hidden ones.

## UX

### Entering / exiting

- Long-press any transaction row → `isSelecting = true`, that row's id added
  to `selectedIDs`. **Gesture is free:** Activity rows use only
  `.swipeActions` (`ActivityView.swift:106`) — no `.contextMenu` or existing
  long-press to collide with.
- **Cancel** (nav bar leading) exits: `isSelecting = false`, `selectedIDs`
  cleared.
- Selection mode is add-mode only for the list; tapping a row toggles its
  membership in `selectedIDs` (does not open the edit sheet while selecting).

### Chrome while selecting

- **Nav bar title:** "N selected" (`String(localized:)`, plural via the
  string catalog, same pattern as the delete banner's
  `"\(count) transaction deleted"`).
- **Nav bar trailing:** **Select All** / **Deselect All** — toggles all
  currently visible (`filteredItems`) rows. Label reflects state: shows
  "Deselect All" once every visible row is selected.
- **Rows:** leading selection circle (filled check when selected, empty
  otherwise). Swipe-to-delete is suppressed while selecting to avoid two
  competing delete affordances.
- **Bottom action bar** pinned over the list: **Delete · Category · Amount ·
  Description**. Entire bar disabled (dimmed, non-interactive) when
  `selectedIDs.isEmpty`.
- Search field and filter chips remain usable. If a filter change hides a
  selected row, it silently drops from `selectedIDs` (selection is
  intersected with visible ids on each `filteredItems` change).

### Actions

Each action collects its input (if any), applies to every id in
`selectedIDs`, exits selection mode, and shows the undo banner.

**Every input sheet shows the affected count** so the overwrite is never a
surprise — the picker/input title reads "Set category for N transactions",
"Set N transactions to …", "Set description for N transactions". This is
what justifies keeping the blunt "amount → one identical value" action: the
count makes the overwrite obvious at the point of confirm.

- **Delete** — no input step. Schedules deletion of the selected snapshots
  through the existing `pendingDeletion` flow.
  Banner: "N transactions deleted · Undo".
- **Category** — presents a category picker sheet (reuse the app's existing
  category chip/list presentation). On pick: each selected row is rewritten
  with the new category (and its `categoryPersistentId`), all other fields
  preserved. Banner: "N transactions updated · Undo".
- **Amount** — presents an amount input (reuse `CurrencyAmountField`). On
  confirm: each selected row's amount is set to the entered value. **Sign is
  preserved per the row's existing sign** (an expense stays negative, income
  stays positive) so a bulk amount edit never silently flips expense↔income.
  Banner: same.
- **Description** — presents a text input. On confirm: each selected row's
  `note` is overwritten with the entered string (empty allowed — clears the
  note). Banner: same.

## Architecture

### Generalize the undo path

The delete flow (`pendingDeletion`, `pendingDeletionTask`, `deleteProgress`,
`showUndoBanner`, the 5s progress ring, `commitPendingDeletion`,
`undoDelete`) is already a reversible-mutation-with-timer. Generalize it so
edits reuse it instead of duplicating the timer/banner:

- Introduce a pending-mutation abstraction the banner drives:
  - `pendingUndoMessage: String` — banner copy (already effectively the
    count-based string).
  - `pendingRevert: (() async -> Void)?` — closure that restores prior
    state when Undo is tapped.
  - The commit-on-timeout path finalizes. **This is the one regression-prone
    spot and gets its own test.** `commitPendingDeletion`
    (`TransactionListViewModel.swift:255`) today unconditionally loops
    `repo.delete` over `pendingDeletion`. Generalizing means the timeout
    path must **branch on mutation kind**: when a `pendingRevert` is armed
    (an edit) and `pendingDeletion` is empty, commit must finalize the edit
    (a no-op — the write already happened) and **must not** fall through to
    the delete loop. A bug here silently deletes nothing or crashes. Keep
    delete's existing "write on commit" behavior for the delete case; for
    edits the write happens up front and `pendingRevert` restores the
    captured prior inputs on undo.
- Keep behavior identical for delete (regression-guarded by existing tests);
  edits are new cases that set `pendingRevert` to re-`update` the captured
  `TransactionInput` snapshots.

Rationale: one banner, one timer, one code path — bulk edit is "apply +
arm undo," bulk delete is the existing "arm delete + commit or undo."
Deferring an unshared second banner implementation is deliberate YAGNI.

### Selection state (`TransactionListViewModel`)

- `var isSelecting: Bool = false`
- `var selectedIDs: Set<PersistentIdentifier> = []`
- On every `filteredItems` change, intersect `selectedIDs` with the visible
  ids so hidden rows drop out (extend the existing `filteredItems.didSet`).
- `toggleSelection(_ id:)`, `selectAllVisible()`, `deselectAll()`,
  `exitSelection()`.
- `selectedSnapshots: [TransactionSnapshot]` — resolves `selectedIDs`
  against `transactions` for the action methods.

### Bulk mutation methods (`TransactionListViewModel`)

- `bulkDelete()` — routes selected snapshots into the existing
  `scheduleDeletion` (plain delete, no recurrence prompt), then
  `exitSelection()`.
- `bulkSetCategory(_ category: CategorySnapshot)` — capture prior inputs,
  loop `repo.update` with the new category, arm undo, `exitSelection()`.
- `bulkSetAmount(_ amount: Decimal)` — capture prior inputs, loop
  `repo.update` writing sign-preserved amount, arm undo, `exitSelection()`.
- `bulkSetNote(_ note: String)` — capture prior inputs, loop `repo.update`
  writing the new note, arm undo, `exitSelection()`.

Each edit method builds each row's new `TransactionInput` from its current
snapshot with the single field changed, so no unrelated field is disturbed.

### Repository

No new methods. Bulk = loop the existing `repo.delete(id:)` /
`repo.update(id:with:)`. A real `updateBatch` is a later optimization —
mark the loop with a `ponytail:` comment naming that upgrade path; add it
only if the loop measurably lags on large selections.

## Interactions & edge cases

- **Empty selection:** action bar disabled; `bulk*` methods no-op on empty.
- **Filter hides a selected row mid-selection:** row drops from
  `selectedIDs` via the `filteredItems` intersection; count updates live.
- **Undo after edit:** `pendingRevert` re-`update`s each captured prior
  `TransactionInput`; list reloads to reflect the restore.
- **Rapid successive bulk actions:** each new action cancels the prior
  pending task/banner (same guard the delete flow already uses), so banners
  don't stack.
- **Recurring occurrence in a bulk delete:** deleted this-only; its
  recurrence rule is untouched.
- **Sign flip guard:** `bulkSetAmount` preserves each row's existing sign, so
  a bulk amount edit can't convert an expense into income or vice versa.

## Testing (Swift Testing, `@Test`/`#expect`)

- `toggleSelection` adds/removes ids; `selectAllVisible` selects exactly the
  filtered set (not hidden rows); `deselectAll` empties.
- Filtering out a selected row removes it from `selectedIDs`.
- `bulkDelete` removes exactly the selected rows and arms the undo banner;
  undo restores them.
- `bulkSetCategory` rewrites category on exactly the selected rows, leaving
  others and other fields untouched; undo restores prior categories.
- `bulkSetAmount` sets the new magnitude on selected rows with sign
  preserved (expense stays negative, income positive); undo restores prior
  amounts.
- `bulkSetNote` overwrites notes on selected rows (including clearing to
  empty); undo restores prior notes.
- Recurring occurrence in `bulkDelete` is deleted without closing its rule.
- Recurring occurrence in a bulk **edit** diverges in value only: its
  category/amount/note changes while it stays linked to its rule (rule and
  future occurrences unaffected); undo restores the prior value.
- **Commit-branch guard (Gap 2):** after an edit's timer elapses, the commit
  path finalizes the edit and does **not** delete any rows — `pendingDeletion`
  stays empty and no `repo.delete` is issued. (Asserts the timeout branch
  never falls into the delete loop for an edit.)
- Regression: single-row swipe delete and its recurrence prompt still behave
  as before (the generalized undo path must not change delete semantics).
- View-layer (manual, device/simulator): long-press enters selection with
  the row selected; action bar enables/disables with the count; undo banner
  appears and reverts for each action; swipe-to-delete is suppressed while
  selecting.
