# Navigation and presentation

- Use `NavigationStack` or `NavigationSplitView` as appropriate; flag all use of the deprecated `NavigationView`.
- Strongly prefer to use `navigationDestination(for:)` to specify destinations; flag all use of the old `NavigationLink(destination:)` pattern where it should be replaced.
- Never mix `navigationDestination(for:)` and `NavigationLink(destination:)` in the same navigation hierarchy; it causes significant problems.
- `navigationDestination(for:)` must be registered once per data type; flag duplicates.

## Adaptive hierarchy

- Keep navigation and selection state stable as available space changes. Compact width may show one pane while regular width shows primary and secondary panes together, but both must represent the same hierarchy and capabilities.
- On the iOS 26 baseline, use `NavigationSplitView`, size classes, safe areas, and `ViewThatFits` for adaptive primary/secondary experiences. Do not branch on device model or orientation.
- The iOS 27.1 beta `ArrangementView` is preview knowledge, not the ordinary recommendation. Evaluate it only on explicit user request and only when two existing content regions naturally form a split or overlay arrangement. Place `NavigationStack`, `NavigationSplitView`, or `TabView` outside it, and preserve an iOS 26 container fallback.
- Standard containers adapt around iPhone Duo reserved regions. Query `GeometryProxy.reservedRegions(...)` only when custom layout needs to avoid a fold or camera occlusion; never replace safe-area handling with a device-specific offset.

## Toolbars and constrained space

- Use semantic `ToolbarItem` and `ToolbarItemGroup` placements. Keep navigation/exit controls first, prominent actions next, and related secondary actions grouped; do not create spacing with fixed toolbar gaps.
- Every toolbar action that is not text-only needs both a title and a symbol. The system can then use the symbol in a vertical bar and the title plus symbol in overflow.
- On iOS 27, use `visibilityPriority(_:)` to keep important actions visible longer, `ToolbarOverflowMenu` to place secondary actions directly in system overflow, and `.topBarPinnedTrailing` only for an action that must remain pinned at the trailing edge. On iOS 26, reduce visible items deliberately and use a standard `Menu` in `.topBarTrailing`.
- Let the system choose horizontal or vertical bars by default. Do not propose the iOS 27.1 beta `axisBehavior(_:)`, `toolbarVerticalBehavior(_:)`, or `toolbarVerticalEdge` APIs in ordinary work. During an explicitly requested beta evaluation, use them only for a demonstrated need, not as a reason to build a custom bar; `toolbarVerticalEdge` reports the preferred edge even when a vertical bar is not currently visible.
- Preserve the same actions when bars rotate or overflow. Priority changes representation and position, not feature availability.


## Alerts, confirmation dialogs, and sheets

- Always attach `confirmationDialog()` to the user interface that triggers the dialog. This allows Liquid Glass animations to move from the correct source.
- If an alert has only a single “OK” button that does nothing but dismiss the alert, it can be omitted entirely: `.alert("Dismiss Me", isPresented: $isShowingAlert) { }`.
- If a sheet is designed to present an optional piece of data, prefer `sheet(item:)` over `sheet(isPresented:)` so the optional is safely unwrapped.
- When using `sheet(item:)` with a view that accepts the item as its only initializer parameter, prefer `sheet(item: $someItem, content: SomeView.init)` over `sheet(item: $someItem) { someItem in SomeView(item: someItem) }`.
- Use the system’s sheet placement unless the relationship to adjacent content requires otherwise. On iOS 27, `presentationPlacement(_:)` can request leading, center, or trailing placement; preserve standard iOS 26 sheet behavior as the fallback.
- On iPhone Duo, inspect sheets and popovers while closed, open, partially folded, and rotated when the feature depends on their placement. Don’t infer a pose from orientation.

## Availability boundary

The app still deploys to iOS 26. Any stable iOS 27.0 navigation, toolbar, or presentation enhancement needs `#available(iOS 27, *)` and an iOS 26 equivalent. Apple currently documents iOS 27.1 APIs as beta: keep them out of ordinary implementation and review recommendations. If the user explicitly requests beta evaluation, also require an SDK that contains the symbols; an availability branch cannot make an unknown symbol compile.

## Apple references

- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Navigation and search](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search)
