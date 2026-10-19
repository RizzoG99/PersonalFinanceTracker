# 13: Trip transaction rows lack vertical spacing (Build 93)

**feedbackIdentifier** `AIxFxfyDLbi4TEmK-XS8OZs` · **Date** 2026-09-21 · **Severity** P3

## Symptom

In the trip detail sheet, transaction rows are rendered with no vertical spacing between them. The tester reports:

> "Le row relative alle transazioni del viaggio, non sono distanziate correttamente. Dovrebbero avere lo stesso layout di 'Transazioni recenti' della Dashboard oppure della lista movimenti."
>
> (The rows for the trip's transactions aren't spaced correctly. They should have the same layout as the Dashboard's "Recent transactions" or the transaction list.)

**Screenshot evidence** (`docs/feedback/ios-2026-09/b93-AIxFxfyD.jpg`): The trip detail displays a list of transactions (Caffè e bevande, Benzina, Trasporto pubblico, Ristoranti, etc.) with category icons on the left, category/note text in the middle, and amounts on the right. The rows are visually cramped—each transaction row is directly adjacent to the next with no whitespace between them, creating a dense, compressed appearance.

**Reference layouts compared:**
- Dashboard "Recent Transactions" section shows the same row type with visible vertical breathing room
- Activity tab transaction list shows proper spacing in a List context

## Root cause

**Branch:** `feature/travel-groups` · **Commit:** `a1f9e22`

The trip detail uses `TravelDetailSheet.swift:242`, which renders transactions in a `VStack` with **zero spacing**:

```swift
// TravelDetailSheet.swift:242-266
GlassCard {
    VStack(spacing: 0) {  // ❌ spacing: 0 (should be 8)
        ForEach(Array(members.enumerated()), id: \.element.id) { index, item in
            Button {
                onSelect(item)
            } label: {
                TransactionItemView(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu { ... }

            if index < members.count - 1 {
                Divider().overlay(Color.hairline)  // ❌ no horizontal padding
            }
        }
    }
}
```

**Reference implementation** in `Dashboard/Components/RecentTransactionsSectionView.swift:20-35`:

```swift
GlassCard {
    VStack(spacing: 8) {  // ✓ spacing: 8
        ForEach(viewModel.recentTransactions) { tx in
            Button {
                transactionListViewModel.transactionToEdit = tx
            } label: {
                TransactionItemView(item: tx)
            }
            .buttonStyle(.plain)
            if tx.id != viewModel.recentTransactions.last?.id {
                Divider()
                    .padding(.horizontal, -16)  // ✓ extends divider to card edges
            }
        }
    }
}
```

**The exact differences:**

| Aspect | Trip Detail | Dashboard Reference |
|--------|------------|---------------------|
| VStack spacing | `spacing: 0` | `spacing: 8` |
| Divider horizontal padding | none | `.padding(.horizontal, -16)` |
| Result | Rows touch edge-to-edge; visually cramped | 8pt vertical breathing room between rows; dividers extend full width |

Both implementations render `TransactionItemView`, which provides the shared row layout (category icon, title/note, amount). The difference is purely in the container spacing and divider styling. The trip detail reuses the correct row component but fails to apply the correct list-like spacing that makes the reference layouts readable.

## Edge cases

- **Empty trip:** The memberSection is only rendered if `members.count > 0` (line 243), so empty trips show no spacing issues.
- **Single transaction:** A trip with one transaction shows no dividers (line 261 checks `index < members.count - 1`), so spacing difference is minimal but still present (the row sits directly against the GlassCard padding).
- **Scrolling context:** The trip detail sheet scrolls via `ScrollView` (line 40 of TravelDetailSheet.swift), not a List. This means no automatic list-style separators are applied, and manual spacing is the only visual separator. The lack of spacing is therefore more noticeable than in a standard List.

## Priority

**Confirm P3.** The layout is visually broken in a way that impacts readability and consistency with reference layouts used elsewhere in the app. It's a UX regression for trip expense tracking, but not a functional bug or crash. It should be fixed before release but is not blocking.

## Open Points

- **GlassCard padding interaction:** The Dashboard dividers use `.padding(.horizontal, -16)` to extend past the default GlassCard padding. Confirm whether the GlassCard's default horizontal padding is 16pt before applying a symmetric fix.

---

## Verification at branch HEAD

**Commit a1f9e22:** The issue **persists** at branch HEAD. The `VStack(spacing: 0)` and missing divider padding remain unchanged. The post-release UX-fix commit `42aaa81` ("Travels: fix the in-trip flows a UX pass turned up", Sep 7) did not address spacing—it fixed "Add expense" flow and member removal. This layout bug was not caught by that UX pass.

## Suggested fix

### Option A: Match Dashboard spacing exactly (low risk)

Change line 242 of `TravelDetailSheet.swift` from:

```swift
VStack(spacing: 0) {
```

to:

```swift
VStack(spacing: 8) {
```

And line 262 from:

```swift
Divider().overlay(Color.hairline)
```

to:

```swift
Divider()
    .padding(.horizontal, -16)
```

**Trade-off:** Straightforward, reuses proven spacing values from the reference. Risk of unintended side effects is minimal since both are direct copies from the working Dashboard component.

### Option B: Extract shared list container (higher cost, better maintainability)

Create a reusable `TransactionListContainer` component that wraps the VStack + Divider + spacing logic, used by both `RecentTransactionsSectionView` and `TravelDetailSheet`.

**Trade-off:** Eliminates future duplication and makes spacing guarantees explicit. Requires refactoring and testing both sites. Better long-term but higher immediate cost.

### Option C: Conditionally apply spacing via a parameter

Pass a `spacing: Double = 8` parameter to a shared component (or a view modifier) that both Dashboard and Trip detail can use.

**Trade-off:** Middle ground. Less refactoring than Option B, but maintains a single source of truth for list styling.

**Recommended:** Option A for immediate fix; evaluate Option B/C as part of a post-release styling unification pass if similar inconsistencies appear elsewhere.
