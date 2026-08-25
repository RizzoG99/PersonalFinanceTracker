# Personal Finance Tracker UI Patterns

Load this reference only when the feature includes the relevant pattern. These rules specialize the app-wide guidance in `design.md`; existing implementations and `Utilities/DesignTokens.swift` remain the source of truth.

## Screen states

Model states explicitly instead of letting missing data accidentally produce blank space or stale content.

| State | UI responsibility |
| --- | --- |
| Loading | Name the work when useful; use indeterminate progress unless the total is real. Preserve stable layout when practical. |
| Populated | Put the primary decision or task first and keep supporting data scannable. |
| Empty | Explain what is missing and, when actionable, provide the clearest next step. |
| No results | Preserve the user's query/filter context and offer Clear Search or Clear Filters. |
| Error | Say what failed and provide a recovery action when one exists. Never disguise failure as emptiness. |
| Disabled | Make the unavailable control visibly disabled and explain the requirement nearby when it is not obvious. |
| Success | Confirm completion briefly without interrupting the next likely action. |

Only implement states the workflow can actually reach. Do not invent fake progress, placeholder errors, or decorative state machinery.

## Empty and unavailable states

Use `ContentUnavailableView` where it fits. Select the copy and action based on the cause:

- **First run:** explain the feature's value and offer the first meaningful action.
- **No content:** state what has not been created or recorded; add one primary creation action when appropriate.
- **No selection:** tell the user what to select; usually no action is needed.
- **No results:** say that the current query or filters matched nothing; keep search/filter controls reachable and offer a reset.
- **Unavailable:** name the missing permission, service, or prerequisite and offer the safest route to recover.
- **Error:** name the failed operation and offer Retry, Settings, or another concrete recovery action.

Keep the pattern calm: one meaningful SF Symbol, a short title, one short explanation, one primary action, and at most one genuinely useful secondary action. A blank screen, “Nothing here,” or an illustration without a next step is not sufficient.

## Feedback and progress

Always make it clear what is happening, what changed, and whether the user needs to act. Choose the least disruptive level that matches the scope:

1. **Inline feedback** for field validation or local row/card state.
2. **ProgressView** for active work. Use determinate progress only when the app knows the total; otherwise name the current operation.
3. **ToastBanner** for brief, nonblocking confirmation or an undo action. Informational toasts appear near the top; actionable/undo toasts near the bottom.
4. **Screen-level banner/card** for a persistent issue that affects the screen while leaving other work available.
5. **Alert** for blocking failures, destructive confirmation, or information that must be acknowledged.
6. **Notification** only for useful background completion or failure when the user may be elsewhere.

Avoid generic “Something went wrong,” fake percentages, indefinite success banners, repeated notifications, and animation-only status. Pair status color and symbols with text and respect Reduce Motion.

## Search, filters, and sorting

Use one stable mental model:

> Search finds text. Filters narrow by structured constraints. Sort changes order.

For Activity, preserve the established architecture:

- `.searchable` owns text search.
- `FilterChipsView` exposes type/date/amount constraints and makes active filters visible.
- `SearchFilters.matches` owns filter semantics.
- `SearchTests` owns behavioral coverage.

Do not duplicate search with a custom field, hide active constraints, or combine sorting into filter semantics. Provide Clear Search and/or Clear Filters whenever state can otherwise be difficult to unwind. A no-results view must distinguish an empty ledger from a query/filter mismatch.

## Toolbars and action placement

Toolbars contain actions for the current screen; navigation belongs to tabs, sidebar, or the navigation stack. Follow these priorities:

- Keep one obvious primary action. On iPhone, the established global primary action is Add Transaction through `AppToolbarModifier` unless the current mode replaces it intentionally.
- Use leading placement for Back, Cancel, Close, or mode exit; use trailing placement for Add, Save, Set, Done, or the current primary action.
- Put infrequent screen-level actions in a `Menu` and item-specific actions in swipe/context menus when discoverability remains adequate.
- Never make destructive actions the prominent default when they can be secondary and confirmed.
- During selection or editing modes, remove or replace conflicting global actions instead of displaying both toolbars.
- Give every symbol-only visual action a semantic text label and preserve a 44x44-point target.

Before finishing, list each toolbar action and answer: does it apply to this screen now, is its placement conventional, and does it compete with the primary action?

## Financial typography and values

Financial content must be fast to compare and difficult to misread:

- Format through the app's currency/date services; never hand-build currency strings in a view.
- Preserve explicit signs or nearby income/expense labels. Color may reinforce direction but cannot carry it alone.
- Use `monospacedDigit()` for values that update in place or align in a comparative row/column when it improves stability. Do not switch ordinary labels or prose to a monospaced font.
- Give one value primary emphasis per card. Supporting totals and percentages must not compete at the same size and weight.
- Anticipate large magnitudes, negative values, decimals, and privacy mode. Essential amounts must not truncate silently.
- Apply `.privacyBlur()` wherever equivalent sensitive amounts already support shake-to-hide, including correct accessibility masking.
- Charts need a textual summary and cannot require color alone to distinguish essential series or categories.

## Pattern review

Before calling the feature complete, check the relevant questions:

- Can the user tell the difference between empty, filtered-to-zero, loading, and failed?
- Does every recoverable failure expose a concrete recovery path?
- Is progress truthful, and is completion feedback proportional?
- Are search, filters, and sort separate and reversible?
- Is there exactly one primary action for the current screen or step?
- Do toolbar actions remain correct in selection/editing modes and compact width?
- Are monetary direction, magnitude, and privacy understandable without relying on color?
- Do state transitions remain understandable with VoiceOver and Reduce Motion?

## Optional static audit

[HIG Doctor](https://github.com/raintree-technology/hig-doctor) can supplement review when it is already installed or the user explicitly asks to add/run it. It catches mechanically detectable issues such as hard-coded SwiftUI colors/font sizes, deprecated navigation, some inaccessible images/tap gestures, and risky layout patterns.

Treat it as a lint layer, not a design system:

- Its findings do not establish visual quality, app-theme consistency, accessibility compliance, or HIG conformance.
- Review findings against intentional shared infrastructure such as `AppBackground`; baseline or suppress only with a concise reason.
- Prefer gating newly introduced concerns rather than failing a feature for unrelated existing debt.
- Do not replace previews, simulator checks, VoiceOver review, or the `design.md` quality gate with a clean audit.
