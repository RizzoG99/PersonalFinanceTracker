# UX/UI Audit — Personal Finance Tracker — ToastBanner Component — 2026-07-30

## Screens audited
- **Activity, privacy toast active** — `ToastBanner` used with no `action` (icon+text only), top-pinned — source: screenshot (pre-fix bug state)
- **Activity, after deleting a transaction** — `UndoDeleteBanner` built on `ToastBanner` with a progress-ring+Undo `action`, bottom-pinned — source: screenshot
- Code-level review: `Utilities/DesignTokens.swift:162-198` (`ToastBanner`), `Features/TransactionListView/TransactionListView.swift:10-39` (`UndoDeleteBanner`), `Features/MainTabView/MainTabView.swift:88-97` (privacy toast call site)

## Per-screen findings

### ToastBanner — no-action case (privacy toast)
- **Severity: Critical (now fixed in this session) — Problem:** The screenshot shows the top toast rendering as a full-width, edge-to-edge black bar with square corners — not the intended compact, centered pill. **Why it hurts UX:** Nielsen's *aesthetic and minimalist design* and Gestalt's *figure-ground* — a bar spanning the entire display width (and appearing to extend behind the status bar with no visible rounding) reads as a rendering glitch, not a deliberate confirmation toast; it also visually competes with the nav bar/toolbar it overlaps. **Root cause (confirmed in code before the fix):** the shared `ToastBanner` had an unconditional `Spacer(minLength: 0)` between the message `Text` and `action()`. A `Spacer` expands to fill *all* width its parent proposes regardless of what follows it — so even with `action: { EmptyView() }`, the `HStack` (and its `Capsule` background) still stretched to the full width offered by `.overlay(alignment: .top)`, which proposes the entire screen width. **Fix applied:** the `Spacer` was moved out of the shared component entirely (`DesignTokens.swift:184-190`) and into `UndoDeleteBanner`'s own `action` closure (`TransactionListView.swift:19-20`), so a no-action caller now gets a `HStack` with no flexible child and naturally hugs its content into a compact pill. **Verification note:** confirmed via a fresh build (green) after the fix; a real device/simulator re-screenshot of the shake-toggle toast would be the ideal final confirmation, not yet captured in this audit.

### ToastBanner — with-action case (UndoDeleteBanner)
- **Strength:** The countdown ring is a strong non-verbal urgency cue, and moving the `Spacer` into this call site's `action` closure preserves its original edge-to-edge stretched layout exactly — no visual regression from the refactor.
- **Severity: Low — Problem:** `UndoDeleteBanner` now silently depends on remembering to add `Spacer(minLength: 0)` as the *first* element of its `action` closure to get the "stretch to trailing edge" look; nothing in `ToastBanner`'s public API signals that this is required or optional. **Why it hurts UX (as a *maintainer* UX/DX issue, not an end-user one):** Nielsen's *visibility of system state* applies to APIs too — a future caller adding a third toast variant with an action (e.g. a "Retry" button) has no signal from `ToastBanner`'s signature that they must choose, and remember, whether to prepend a `Spacer`. Get it wrong and they'll reproduce today's exact bug. **Recommendation:** see "sound pattern?" verdict below — don't over-fix this with a parameter/enum; a one-line doc comment (already added) plus a self-check are enough for a two-call-site component. If a third variant appears, promote the leading-space decision to an explicit parameter then, not now.

## Is the "Spacer ownership delegated to the caller" pattern sound?

**Verdict: sound for two call sites, worth revisiting only if a third distinct toast shape appears.** Reasoning:
- It correctly fixes the actual defect: a shared component should never assume how its `action` slot will be laid out relative to the message, since "hug content" and "push to trailing edge" are genuinely different, valid designs (informational pill vs. actionable bar), not two settings of the same knob.
- The alternative — an internal `Spacer` gated by `Action.self == EmptyView.self` type-checking, or a `spacesAction: Bool` parameter — adds a boolean/generic-comparison special case to solve a problem the caller can already solve by writing one extra line (`Spacer(minLength: 0)`) in their own `@ViewBuilder` closure. That's exactly the kind of "special case layered on shared infrastructure" to avoid: it doesn't reduce total code, it just moves the same conditional into the shared component and makes `ToastBanner` responsible for a layout decision only the caller actually has context for.
- The risk this pattern trades in return (documented above) is a **documentation/discoverability cost for the next contributor**, not a runtime or user-facing risk — acceptable at 2 call sites, worth a real parameter (e.g. `layout: .compact` vs `.stretched`) only once a third caller needs to make this same choice and the "read the doc comment" convention starts failing in practice.

## Cross-screen consistency issues

1. **No automated regression guard for pill shape.** This exact bug (Spacer swallowing the compact-pill case) could recur silently if a future edit re-adds a shared `Spacer` "to be safe" — there's no snapshot/UI test catching a toast's rendered width. Not proposing a full snapshot-testing setup for two toasts, but worth a mental flag: if a third `ToastBanner` caller is added, that's the moment to add one lightweight layout assertion (e.g. asserting the `HStack` has no `.frame(maxWidth: .infinity)` propagation) rather than relying on visual re-inspection each time.
2. **The outer `.padding(.horizontal, 16)` at the privacy-toast call site (`MainTabView.swift:95`) is now vestigial** for typical Dynamic Type sizes (the pill hugs its content well inside that ceiling) but is cheap, harmless insurance against the pill ever touching the screen edge at very large accessibility text sizes. Fine to keep as-is; flagging only so it's understood as intentional headroom, not dead code.

## Executive Summary
- **Top problem (now fixed):** shared `Spacer` in `ToastBanner` stretched the no-action toast to full width.
- **Top remaining risk:** the "who owns the Spacer" convention is implicit — a doc comment covers 2 call sites; a 3rd should get an explicit parameter.
- **Biggest accessibility win already in place:** `ToastBanner` deliberately does *not* auto-combine accessibility children, preserving the Undo button's tappability — correctly reasoned in the existing code comment.

## Quick Wins
- None outstanding — the layout fix and the doc comment already cover this component at its current scope.

## High Impact Improvements
- If/when a third toast variant is added, promote the implicit "who adds the Spacer" convention into an explicit `ToastBanner` parameter (e.g. `trailingLayout: .hug | .stretch`) instead of relying on the doc comment — turns a discoverability risk into a compiler-enforced choice.

## Long-term Improvements
- Consider a lightweight `ViewInspector`-based (or manual `UIHostingController`-measured) unit test asserting `ToastBanner(action: { EmptyView() })` renders at its intrinsic content width, not the full proposed width — cheap insurance against this exact regression recurring, appropriate once a 3rd caller raises the maintenance stakes.

## UX Score (1–10, this component)
- **Visual Design:** 8 — clean capsule pill, consistent with the app's existing pill language, once the fix is applied.
- **Usability:** 8 — both toast variants communicate state clearly; auto-dismiss timing is reasonable for each's purpose.
- **Accessibility:** 7 — correct `accessibilityHidden`/label handling and deliberate non-combining default; still no proactive `UIAccessibility` announcement (carried over from the prior toast-comparison audit, not re-scored down here since it's not new).
- **Consistency:** 8 — one shared primitive now backs both toasts; the only inconsistency is the undocumented-until-now Spacer convention, which is now documented.
- **Overall:** 8 — solid component, correctly scoped fix, no over-engineering introduced.

## Redesign Suggestions
No redesign needed — the current shape (shared `ToastBanner` + caller-owned `Spacer`) is the right level of abstraction for two call sites. If a third toast variant is ever added with a different layout need, that's the trigger to add an explicit layout parameter rather than a third undocumented convention:

```swift
enum ToastLayout { case hug, stretch }

struct ToastBanner<Action: View>: View {
    let icon: String
    let message: String
    var layout: ToastLayout = .hug
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            Text(message).font(.subheadline.weight(.semibold))
            if layout == .stretch { Spacer(minLength: 0) }
            action()
        }
        // ...
    }
}
```

This is a **future** suggestion, not a change to make today — the current two-call-site code is simpler and correct, and adding the enum now would be solving a problem that doesn't exist yet.
