# Feature: Travel expense groups

## Decision summary

A **Travel** is a named folder for trip expenses. Transactions are tagged into it
explicitly; the Activity list renders the folder as a single row
(`✈️ Barcellona Travel · 6 expenses · −€400,00`) and a bottom sheet reveals the
members.

This direction won because it is the only one that is true regardless of how the
user travels, and because it changes nothing outside the Activity list. Budgets,
CategoryBreakdown and Insights keep seeing a €60 Barcelona dinner as a €60 Food
expense. A trip budget or a trip report can be layered on later without redoing
the substrate.

## Problem and outcome

A trip is one mental event but a dozen scattered rows. After returning from
Barcelona the user cannot answer "what did that trip cost me?" without adding it
up by eye, and the trip rows bury a month of ordinary spending in Activity.

Outcome: one glanceable trip total in the transaction list, with the detail one
tap away, and no distortion of the app's existing spending analysis.

## User experience

**Create.** Activity toolbar → *New Travel* → name + emoji (default ✈️) → the
empty trip sheet opens.

**Tag an existing expense.** Edit the transaction → *Travel* picker, occupying
the same slot as today's Goal picker.

**Tag while travelling.** Open the trip sheet → *+ Add expense* → the add form
opens with the trip pre-filled. This is the primary in-trip flow and the reason
explicit tagging is not a chore.

**Read.** The trip row sits in the day section of its **most recent** member.
While travelling it naturally rides near the top of Activity; once home it
settles chronologically where the trip ended. Tapping opens a bottom sheet with
the trip name, total, and the member transactions as normal rows, each tappable
through to the real edit sheet. Rename and delete live in this sheet.

## Key states and edge cases

- **Search or filter active → do not collapse.** If the user searched "dinner"
  they want the dinner, not the folder. Collapsing only in the unfiltered list
  leaves `SearchFilters.matches` untouched.
- **Delete a Travel** keeps the expenses and nullifies their `travelId`. The
  confirmation dialog must say so explicitly — the user is deleting a folder,
  not €400 of history.
- **Income inside a trip** (a friend paying the user back) nets against the
  total. Signed `Decimal` handles this with no special case; a trip could in
  principle net positive.
- **Empty trip** shows €0 and remains visible in the list, otherwise it cannot
  be found in order to be filled.
- **Single-member trip** still renders as a folder row, not a bare transaction —
  consistency beats cleverness here.

## MVP

- `TravelModel`: id, name, emoji.
- `travelId: UUID?` on `TransactionModel`.
- Travel picker in the add/edit transaction sheet.
- Collapsed trip row in Activity (unfiltered list only).
- Trip detail bottom sheet: total, member list, *+ Add expense*, rename, delete.
- `travelId` and the travels array carried through snapshots and backup.

## Non-goals

- Trip budgets or progress bars.
- Per-trip reports: category breakdown, cost per day, trip-to-trip comparison.
- Automatic membership by date range or location.
- Splitting expenses with other people / who-owes-what.
- Per-trip currency (EUR is hardcoded app-wide).
- Collapsing trips anywhere outside the Activity list.

## Product decisions

- **Grouped in the list only, not everywhere.** Making the trip a real €400 line
  item would force a single category onto it and either break the Food budget or
  double-count. A lens over the list costs nothing downstream.
- **Explicit tagging over date ranges or an "active trip" mode.** Date ranges
  swallow the rent charge that lands mid-trip and miss the flight booked three
  months early; an active-trip mode quietly eats weeks of normal spending when
  forgotten. Predictability won, with *+ Add expense* inside the sheet as the
  ergonomic answer to the tagging burden.
- **A folder, not a budget.** A planned amount forces the user to guess before
  leaving and nags when wrong. The folder is the substrate a budget would need
  anyway.
- **The trip row anchors to its latest member.** Activity sections strictly by
  day; a multi-day trip has no natural single date. Anchoring to the most recent
  expense avoids inventing a pinned section that would clutter with old trips.

## Technical considerations

Confirmed from the repository:

- `TransactionModel` already carries `goalId: UUID?` — a loose-UUID grouping
  precedent. `travelId: UUID?` slots in identically; no SwiftData relationship
  graph needed.
- Goals are the structural template end to end: `GoalModel` plus
  `AddGoalSheet` / `GoalDetailSheet` / `GoalCard` / `GoalsSection`, with `goalId`
  threaded through `EditAddTransactionViewModel`, `TransactionListViewModel`,
  `Snapshots.swift`, `BackupModels.swift` and `TransactionActor`. Travel follows
  the same seams.
- `ActivityView.groupedFiltered` is `[(String, [TransactionSnapshot])]`, sectioned
  by day. Collapsing happens at this layer.
- `BackupModels.swift` carries `goalId` in four places; `travelId` must be added
  alongside or trips evaporate on restore.
- Per project policy the app is not on the App Store, so the schema change needs
  no migration — reinstall is acceptable.

Proposals, not yet confirmed:

- Travels are few and small; a plain fetch in `TransactionListViewModel` should
  be sufficient, no dedicated caching.
- Reuse the `"emoji label"` convention already used by categories for the trip
  row icon.

## Success signals

- The user can state a past trip's total from the Activity list without opening
  anything.
- Trips actually get filled — expenses per trip stays well above 1, meaning
  *+ Add expense* is being used rather than abandoned after the first tag.
- Budget and Insights figures are unchanged by the presence of a trip.

## Open questions

- Should the trip sheet offer a way to bulk-tag existing transactions
  retroactively, or is per-transaction editing enough for the first release?
- Does the iPad layout (`IPadSection`) need a Travel entry, or does the Activity
  section cover it?
- Should trips ever be archived, or does the chronological anchor keep old trips
  out of the way on its own?

## Where to start

`TravelModel` + `travelId` on `TransactionModel` + the picker in the add/edit
sheet. That much is testable on its own — tag two transactions, assert they
share a `travelId` and that the sum is right — and it proves the data shape
before any of the collapsing UI exists.
