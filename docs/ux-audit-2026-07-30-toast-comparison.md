# UX/UI Audit — Personal Finance Tracker — Toast/Banner Component Comparison — 2026-07-30

## Screens audited
- **Dashboard, privacy toggle active** — `PrivacyToastView` ("Amounts hidden"), pinned top — source: screenshot
- **Activity, after deleting a transaction** — `UndoDeleteBanner` ("1 transaction deleted", Undo), pinned bottom — source: screenshot
- Code-level review: `Features/MainTabView/MainTabView.swift:88-96, 146-165` (`PrivacyToastView`), `Features/TransactionListView/TransactionListView.swift:10-50` (`UndoDeleteBanner`)

## Per-screen findings

### PrivacyToastView ("Amounts hidden")
- **Severity: Medium — Problem:** This is a second, independently-implemented "black pill toast" component (`MainTabView.swift:148-165`) built from scratch rather than reusing/generalizing `UndoDeleteBanner` (`TransactionListView.swift:10-50`). The two are visually near-identical — rounded black pill at ~75% opacity, white foreground, icon + text, horizontal padding 16 — but exist as two separate `View` structs in two unrelated files. **Why it hurts UX:** Nielsen's *consistency and standards* — not a user-visible defect today because the two happen to look alike, but the duplication is the actual risk: the next toast anyone adds (a third one-off) has no shared component to reach for, and any future visual tweak (radius, opacity, padding) has to be applied twice by hand or the two will silently drift apart. **Recommendation:** extract a single `ToastBanner` view parameterized by icon, message, and optional trailing action (`Button` or `nil`), placed in `Utilities/DesignTokens.swift` alongside `GlassCard`/`UndoDeleteBanner`'s neighbors. `PrivacyToastView` becomes `ToastBanner(icon: ..., message: ..., action: nil)`; `UndoDeleteBanner` becomes the same view with its Undo button + progress ring as the action slot.
- **Severity: Low — Problem:** Auto-dismiss timing (1.5s, `MainTabView.swift:139`) is a bare literal with no comment explaining the choice, and no relationship to `UndoDeleteBanner`'s dismiss window (governed by `viewModel.deleteProgress`, likely ~5s given the ring-countdown pattern). **Why it hurts UX:** two toasts with meaningfully different lifetimes reads as inconsistent pacing if a user encounters both features close together — the privacy toast disappearing 3-4x faster than the delete banner has no explained rationale. **Recommendation:** not necessarily wrong (a passive confirmation *should* dismiss faster than an undo window that gates a destructive action), but worth a one-line comment stating that intentionally, so a future editor doesn't "fix" the mismatch.
- **Strength:** Placement (top) is the right call and is itself a point of *good* differentiation from `UndoDeleteBanner` (bottom) — it avoids the two toasts ever visually colliding or stacking if both were ever triggered in the same moment (e.g. shake right after a delete), and top placement doesn't fight with the tab bar the way a second bottom banner would.
- **Severity: Low — Problem:** No haptic/accessibility announcement beyond the visual toast — `accessibilityElement(children: .combine)` (`MainTabView.swift:163`) is present and correct, but VoiceOver only hears the toast if it happens to be focused when the transient view appears; there's no `.accessibilityAnnouncement` posting the state change proactively. **Why it hurts UX:** WCAG / screen-reader parity — a sighted user gets an unmissable pill banner, but a VoiceOver user navigating elsewhere on screen may never have this element read at all before it auto-dismisses in 1.5s. **Recommendation:** post `UIAccessibility.post(notification: .announcement, argument: "Amounts hidden")` (or the SwiftUI `AccessibilityNotification.Announcement` API) alongside showing the toast, so the state change is announced regardless of current VoiceOver focus.

### UndoDeleteBanner ("1 transaction deleted")
- **Strength:** The countdown ring (`Circle().trim(from: 0, to: 1 - progress)`) is a nice, non-verbal affordance communicating "this window is closing" — better than a bare "Undo" button with no urgency cue.
- **Severity: Low — Problem:** Bottom placement sits at a fixed `.padding(.bottom, 90)` (`MainTabView.swift:84`) tuned to clear the tab bar on this specific screen; if the same banner component were ever reused on a screen with a different bottom-safe-area (e.g. a modal sheet), the hardcoded 90pt offset would need re-tuning by hand at each call site. **Why it hurts UX:** not visible today (single call site), but it's the same "no shared component to inherit safe positioning from" problem as the toast duplication above — confirms the recommendation to unify.

## Cross-screen consistency issues

1. **Two toast implementations, one visual language.** As covered above — this is the core finding. The fact that the user had to ask "did you make a new component?" and the answer is "yes, a visually-identical one" is itself evidence the current code doesn't communicate its own reuse story clearly enough during implementation.
2. **Positioning convention is inconsistent but arguably intentional.** Top (privacy) vs. bottom (undo) isn't a bug — it's a reasonable convention (passive status pill up top, actionable/destructive-adjacent banner near the thumb at the bottom) — but it's implicit, not documented anywhere. If a third toast gets added later, nothing in the code states the rule "informational → top, actionable → bottom."

## Executive Summary
- **Top UX problem:** Component duplication — one `ToastBanner` primitive should back both, parameterized by an optional trailing action.
- **Top accessibility gap:** Neither toast proactively announces to VoiceOver; both rely on ambient focus.
- **Top consistency issue:** No documented rule for top-vs-bottom placement, despite both call sites following one in practice.

## Quick Wins
- Add a one-line comment at each call site stating the top/bottom placement convention, so it reads as a decision, not an accident.
- Add `UIAccessibility.post(.announcement, ...)` to `PrivacyToastView`'s appearance (and consider the same for `UndoDeleteBanner`).

## High Impact Improvements
- Extract a shared `ToastBanner(icon:message:action:)` view in `Utilities/DesignTokens.swift`. Rebuild both `PrivacyToastView` and `UndoDeleteBanner` on top of it. This is a pure refactor (no behavior change) that removes the duplication risk before a third toast compounds it.

## Long-term Improvements
- If a third transient-toast need shows up (e.g. "CSV imported", "Budget saved"), promote the shared `ToastBanner` into a small queueing/presentation system (one active toast at a time, FIFO) rather than each feature managing its own `@State` + `Task.sleep` dismiss timer independently, which is what both current implementations do today.

## UX Score (1–10, this component pair only)
- **Visual Design:** 8 — both toasts are visually polished and match the app's dark glass aesthetic.
- **Usability:** 7 — clear, legible, good placement logic; docked slightly for no proactive a11y announcement.
- **Accessibility:** 6 — `accessibilityElement(children: .combine)` present, but no announcement API used; transient content risks being missed entirely by VoiceOver.
- **Consistency:** 5 — visually consistent by coincidence, not by shared code; the duplication is the real deduction here.
- **Overall:** 7 — good user-facing result today, moderate technical-debt risk if left unaddressed.

## Redesign Suggestions
Shared primitive sketch:

```swift
struct ToastBanner<Action: View>: View {
    let icon: String
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            Text(message).font(.subheadline)
            Spacer(minLength: 0)
            action()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background { Capsule().fill(Color.black.opacity(0.75)) }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

// Privacy toast:
ToastBanner(icon: hidden ? "eye.slash.fill" : "eye.fill", message: hidden ? "Amounts hidden" : "Amounts shown") { EmptyView() }

// Undo banner:
ToastBanner(icon: "trash", message: "\(count) transaction\(count == 1 ? "" : "s") deleted") {
    ZStack { /* progress ring */ }
    Button("Undo", action: onUndo)
}
```
