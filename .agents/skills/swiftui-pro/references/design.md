# Personal Finance Tracker UX/UI Guide

Use this guide for every new or materially changed user-facing view. It combines Apple platform conventions with the visual language already established in the app. Existing primitives in `Utilities/DesignTokens.swift` are the implementation source of truth.

## Design intent

The app should feel calm, trustworthy, and native. Financial information is dense, so visual decoration must support scanning and decision-making rather than compete with it. Use the system's interaction patterns and accessibility behavior, then express the app's identity through its background, glass surfaces, semantic colors, and restrained category accents.

Do not design a feature in isolation. A successful screen should look as if it shipped with Dashboard, Activity, Insights, Credit, and Settings.

## Design principles

Use Apple’s current principles as decision criteria when requirements compete:

- **Purpose:** prioritize the task and information that make the feature valuable.
- **Agency:** keep people informed, avoid trapping them in a flow, and make mistakes recoverable.
- **Responsibility:** protect financial data, explain consequential behavior, and collect or expose only what is necessary.
- **Familiarity:** build on native patterns and apply established app behavior consistently.
- **Flexibility:** preserve context and capability across sizes, input methods, accessibility settings, and device configurations.
- **Simplicity:** include what is necessary, use concise language, and establish a clear hierarchy.
- **Craft:** make deliberate, tested choices and maintain them as the platform evolves.
- **Delight:** support the intended feeling without letting decoration obstruct the task.

These principles are a lens, not a scoring checklist. When two choices are both platform-valid, prefer the one that better protects trust, preserves agency and context, and keeps the primary financial task clear.

## Required preflight

Before writing a new view:

1. Inspect `Utilities/DesignTokens.swift` and the two closest existing screens or components. Choose references that match the interaction, not merely the feature name—for example, inspect another edit sheet for a new edit sheet.
2. Write down the screen's primary task, primary action, navigation/presentation style, and states: loading, populated, empty, error, disabled, and success where applicable.
3. Decide which existing app primitives and native SwiftUI containers satisfy the design. Reuse them before introducing a new component or token.
4. Decide whether the view is meaningfully exposed to iPhone Duo concerns: resizing between compact and regular width, primary/secondary content, custom full-bleed geometry, sheets/popovers, reserved regions, or toolbars that can become vertical. If so, include the Duo checks below; do not add device-specific branches to an unaffected view.
5. Keep one obvious primary action per screen or step. Secondary actions must be visually quieter; destructive actions use a destructive role and confirmation proportional to their consequence.

When any of those states, search/filter/sort, a toolbar, or financial-value presentation is part of the feature, read `ui-patterns.md` before implementation.

If the proposed UI conflicts with an established app convention, preserve the convention unless the task explicitly includes changing the design system.

## App visual language

### Foundations

- Use `.appBackground()` for full-screen destinations. Use `.presentationBackground { AppBackground() }` for sheets when their root does not already paint the background.
- Use `GlassCard` for grouped dashboard, insight, activity, and summary content. Prefer its default padding and radius. Use a smaller existing radius only when matching a compact peer component.
- Use `Form` for settings and data entry. Pair it with `.appFormBackground()` and `.appFormSectionBackground()`; do not recreate form rows as custom cards.
- Apply `.readableWidth()` to form-like or reading-heavy content that can appear on iPad or wide layouts.
- Reuse shared elements such as `AppToolbarModifier`, `ToastBanner`, category tokens, privacy blur, and existing feature components when their semantics match.

### Color

- Use semantic app tokens, never ad-hoc RGB/hex values or UIKit colors in feature views.
- `accentIndigo` communicates the primary action, selection, or navigation emphasis. Apply it judiciously: broad use on controls dilutes the brand and overwhelms the interface. Prefer it for the primary action or meaningful status, and let restrained brand color live in the content layer where it can scroll beneath Liquid Glass controls.
- `positive` and `negative` communicate financial direction or semantic success/danger. Do not rely on color alone; pair them with a sign, label, icon, or position.
- `textPrimary`, `textMid`, and `textDim` form the app's text hierarchy. `hairline` is for subtle separators and strokes; `surfaceRaised`/`formRow` are low-elevation fills.
- Category colors identify category data. Use them as restrained accents, not full-screen backgrounds or competing calls to action.
- Add a color asset or token only when an existing semantic token cannot express a reusable meaning across multiple views. Support light and dark appearances.

### Typography and content hierarchy

- Use Dynamic Type text styles (`title`, `headline`, `body`, `subheadline`, `caption`) rather than fixed sizes. Fixed/scaled display typography is reserved for a genuine hero value and should match an existing app component.
- A screen normally needs: navigation title, optional section heading, primary values, supporting labels, and secondary metadata. Avoid multiple elements competing at the same emphasis.
- Use `.bold()` for bold emphasis. Use other explicit weights sparingly and only to match an established peer.
- Avoid `.caption2`; use `.caption` carefully for nonessential metadata that remains understandable at accessibility sizes.
- Keep financial values aligned and consistently formatted through the app's currency/date services. Expenses remain negative and income positive in the model; presentation must make the direction unambiguous.
- User-facing strings must be localizable. Prefer concise labels that describe the action or value; do not use an icon as the only source of meaning.

### Layout and surfaces

- Start with native `NavigationStack`, `TabView`, `ScrollView`, `List`, `Form`, `Section`, `Grid`, and sheet presentation behavior. Preserve safe areas and system bars.
- Avoid `UIScreen.main.bounds`. Prefer adaptive layout, `containerRelativeFrame()`, `ViewThatFits`, size classes, or `GeometryReader` only when the child genuinely needs the proposed size.
- Avoid fixed widths/heights for text-bearing content. The UI must survive compact width, landscape, iPad, localization, and accessibility Dynamic Type.
- Use spacing already present in the closest peer component. If a value becomes repeated system-wide, promote it to a named token rather than scattering literals.
- Preserve the app's restrained surface hierarchy. Do not nest multiple decorative cards, borders, shadows, gradients, or glass effects without a clear information-hierarchy reason.
- Liquid Glass is for navigational, floating, or grouped surfaces where translucency helps establish elevation. Do not apply glass independently to every row or control.

### App icon boundaries

- Treat the app icon as a separate brand asset, not as a source of in-app decoration. Do not change it as a side effect of ordinary UI work.
- When an icon change is explicitly requested, prefer a simple layered design made for Icon Composer, keep its core features consistent across default, dark, clear, and tinted appearances, and test at small sizes.
- Provide clean, unmasked layers and let the system apply rounding, Liquid Glass highlights, refraction, translucency, blur, and shadows. Do not bake those effects into the artwork.

## Native interaction conventions

- Prefer native controls and behaviors: `Button`, `Menu`, `Picker`, `Toggle`, `DatePicker`, `TextField`, `.searchable`, `swipeActions`, `confirmationDialog`, `alert`, and toolbars.
- Use `Label` for icon-and-text actions. An icon-only visual control must still have a text label, for example `Button("Add transaction", systemImage: "plus", action: add)` with an appropriate label style.
- Never use `onTapGesture` as a button substitute. Interactive targets must be at least 44x44 points and expose disabled, selected, focused, and pressed states appropriately.
- Put Cancel/Close in the leading toolbar position and the committing action in the trailing position for modal editing flows. Disable commit until input is valid rather than accepting and failing silently.
- Use a sheet for a focused, dismissible task and navigation for drilling into content. Avoid stacked sheets when one navigation flow can contain the task.
- Use system feedback patterns: inline validation near the field, `ContentUnavailableView` for empty/search states, `ProgressView` for indeterminate work, alerts for blocking failures, and `ToastBanner` for brief nonblocking status. Do not use a toast for information the user must act on.
- Animation must communicate state change, not decorate it. Respect Reduce Motion and avoid broad implicit animations.

## iPhone Duo and resizable layouts

Apply this section only when the preflight identifies a relevant adaptive-layout, presentation, reserved-region, or toolbar concern.

- Build for resizing, not for a named device pose. Use the compact outer display and regular inner display as stress cases, but make decisions from container size, size classes, layout margins, and safe areas rather than device type or orientation.
- Preserve functionality, information hierarchy, selection, editing state, scroll/search context, and the relative location of actions as the app moves between displays or sizes. A larger layout may reveal an additional hierarchy level; it must not become a different workflow.
- Prefer system containers such as `NavigationStack`, `NavigationSplitView`, `TabView`, `List`, and standard sheets because they adapt around cameras, the fold, and vertical bars. Use `ViewThatFits` or an adaptive custom `Layout` for iOS 26 when a standard container is insufficient.
- Respect asymmetric safe areas. Standard containers account for reserved regions automatically. In ordinary work, keep custom content safe with iOS 26-compatible margins, safe areas, and adaptive containers. Query iOS 27.1 `ReservedRegion` values only during an explicitly requested beta evaluation, when custom content would otherwise cross a fold or camera occlusion.
- For primary/secondary interfaces, collapse to one focused pane in compact width and expose both panes when space permits. Prefer the stable iOS 26 `NavigationSplitView` path. Consider the iOS 27.1 beta `ArrangementView` only when the user explicitly asks to evaluate preview APIs, the content naturally maps to a split or overlay arrangement, and the SDK supports it; keep navigation outside the arrangement view.
- Let system toolbars, tab bars, and navigation controls adopt vertical placement. Preserve semantic grouping and conventional order: navigation/exit first, prominent actions next, then related secondary groups. Don’t override the system’s vertical behavior without a concrete presentation need.
- Give non-text-only toolbar items both a title and an SF Symbol so the system can choose an icon in a vertical bar and an icon plus title in overflow. Preserve the same actions in every pose; lower-priority actions may move to the system overflow menu.

## Accessibility and privacy

- Support Dynamic Type without truncating essential content or hiding actions. Check at an accessibility size, not only the default.
- Provide meaningful VoiceOver labels/values and a logical reading order. Decorative images are hidden; meaningful charts and visualizations have textual summaries.
- Preserve sufficient contrast in light and dark appearance. Do not encode income/expense, status, or selection with color alone; honor Differentiate Without Color.
- Respect Reduce Motion, Increase Contrast, and Reduce Transparency where applicable. Prefer system materials and semantic assets because they adapt automatically.
- Apply `.privacyBlur()` to newly displayed account totals or transaction amounts when equivalent existing content supports shake-to-hide. Never leave a sensitive value visually hidden but exposed to accessibility.

## Quality gate before completion

An agent must not call a UI feature complete until it has checked:

- **Consistency:** compared side by side with the two chosen peer screens; reuses app background, surfaces, tokens, components, navigation, and terminology.
- **State coverage:** populated, empty, loading, error, disabled, success, and destructive flows are handled when relevant.
- **Adaptivity:** checked on a compact iPhone and the relevant wide/iPad layout, including landscape if the workflow can be used there.
- **iPhone Duo, when relevant:** checked while closed, open, partially folded, and rotated; state and functionality remain continuous, safe/reserved regions do not obscure content, and vertical bars preserve action order and access. If the required simulator is unavailable, review the stable responsive fallback and report the device-specific check as open. Treat an unavailable iOS 27.1 SDK as a blocker only when the user explicitly requested beta evaluation.
- **Appearance:** checked in light and dark mode.
- **Accessibility:** checked at an accessibility Dynamic Type size, with VoiceOver labels/traits reviewed and 44x44 targets preserved; Reduce Motion/color-only distinctions considered.
- **Content stress:** checked with long localized-style text, large/negative monetary values, and enough data to expose wrapping, clipping, and scrolling problems.
- **Platform behavior:** keyboard avoidance, focus, dismissal, navigation, sheet detents, safe areas, destructive confirmations, and feedback behave like native iOS UI.
- **Engineering:** a representative `#Preview` uses `SampleData.populateModelContext()` where model data is needed; relevant tests and `scripts/xcb build` pass. If HIG Doctor is already available or the user requests it, run it as an additional static audit, review each finding in app context, and document justified suppressions. Never install it implicitly or treat a clean scan as visual/HIG verification.

If visual execution cannot be run, say so explicitly and leave the UI verification item open rather than claiming the design is verified.

## Apple references

Use the current Apple Human Interface Guidelines as the authority when this guide does not answer a platform question:

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Branding](https://developer.apple.com/design/human-interface-guidelines/branding)
- [Searching](https://developer.apple.com/design/human-interface-guidelines/searching)
- [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
