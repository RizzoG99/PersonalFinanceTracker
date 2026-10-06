# Using modern SwiftUI API

## Deployment and SDK availability

The project’s deployment target remains iOS 26. Newer SDK knowledge does not authorize raising it. Use a stable iOS 27.0 API only behind the matching availability boundary and with an equivalent iOS 26 path. An availability check handles runtime compatibility; it does not make a symbol compile with an older SDK.

Apple currently marks the iOS 27.1 APIs below as beta. They are preview notes for future planning, not recommendations for ordinary implementation or review. Do not propose or reference them unless the user explicitly asks to evaluate beta APIs. Even then, first confirm that the selected Xcode SDK exposes the symbols and preserve an iOS 26 fallback.

```swift
if #available(iOS 27.0, *) {
    modernContent
} else {
    iOS26Content
}
```

Keep the fallback behaviorally complete. A newer API may improve placement or adaptation, but must not make an action, state, or essential content exclusive to iOS 27.

## iOS 27 conditional capabilities

| API | Availability and intended use | iOS 26 fallback |
| --- | --- | --- |
| `visibilityPriority(_:)` | iOS 27.0. Apply to toolbar content so important groups/items remain visible longer as space contracts. | Keep the essential action visible and group secondary actions in a standard toolbar `Menu`. |
| `ToolbarOverflowMenu` | iOS 27.0. Put infrequent toolbar actions directly in the system overflow menu; don’t create a second ellipsis menu. | Use a labeled `Menu` in a semantic toolbar placement. |
| `.topBarPinnedTrailing` | iOS 27.0. Pin a genuinely critical action to the trailing toolbar edge. Avoid pinning multiple competing actions. | Use `.topBarTrailing` and keep one primary action. |
| `presentationPlacement(_:)` | iOS 27.0. Request automatic, leading, center, or trailing placement when a sheet’s relationship to surrounding content requires it. | Use the standard sheet and detent behavior; don’t simulate placement with fixed offsets. |

## iOS 27.1 beta preview — explicit opt-in only

| API | Availability and intended use | iOS 26 fallback |
| --- | --- | --- |
| `ArrangementView` | iOS 27.1 beta. Adapt primary and secondary content as a split or overlay in response to size and reserved regions. Keep navigation outside it. | Use `NavigationSplitView` for hierarchy, or `ViewThatFits`/adaptive stacks for pure layout. |
| `ReservedRegion` and `GeometryProxy.reservedRegions(...)` | iOS 27.1 beta. Inspect fold divisions or camera occlusions only for custom layouts that system containers cannot adapt automatically. | Respect safe areas and margins, use standard containers, and keep critical content away from fragile full-bleed geometry. |
| `toolbarVerticalEdge` | iOS 27.1 beta. Read the system’s preferred vertical-bar edge to position custom adjacent UI; it does not prove a vertical bar is visible. | Let safe areas and standard bar containers determine placement. |
| `axisBehavior(_:)` | iOS 27.1 beta. Declare whether a toolbar item is automatic, vertical-preferred, or horizontal-only. Horizontal-only items can disappear when no horizontal bar exists, so don’t use it for an essential action. | Use adaptive `Label` content and semantic toolbar placement. |
| `toolbarVerticalBehavior(_:)` | iOS 27.1 beta. Keep `.automatic` unless a specific presentation, such as a sheet, must disable vertical bars. | Use the system’s standard horizontal toolbar behavior. |

## Apple API references

- [`visibilityPriority(_:)`](https://developer.apple.com/documentation/swiftui/toolbarcontent/visibilitypriority(_:))
- [`ToolbarOverflowMenu`](https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu)
- [`topBarPinnedTrailing`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbarpinnedtrailing)
- [`presentationPlacement(_:)`](https://developer.apple.com/documentation/swiftui/view/presentationplacement(_:))
- [`ArrangementView`](https://developer.apple.com/documentation/swiftui/arrangementview)
- [`ReservedRegion`](https://developer.apple.com/documentation/swiftui/reservedregion)
- [`reservedRegions(kind:options:layoutDirectionBehavior:)`](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:))
- [`toolbarVerticalEdge`](https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarverticaledge)
- [`axisBehavior(_:)`](https://developer.apple.com/documentation/swiftui/toolbarcontent/axisbehavior(_:))
- [`toolbarVerticalBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/toolbarverticalbehavior(_:))

## General modern API guidance

- Always use `foregroundStyle()` instead of `foregroundColor()`.
- Always use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`.
- Always use the `Tab` API instead of `tabItem()`.
- Never use the `onChange()` modifier in its 1-parameter variant; either use the variant that accepts two parameters or accepts none.
- Do not use `GeometryReader` if a newer alternative works: `containerRelativeFrame()`, `visualEffect()`, or the `Layout` protocol. Flag `GeometryReader` usage and suggest the modern alternative.
- When designing haptic effects, prefer using `sensoryFeedback()` over older UIKit APIs such as `UIImpactFeedbackGenerator`.
- Use the `@Entry` macro to define custom `EnvironmentValues`, `FocusValues`, `Transaction`, and `ContainerValues` keys. This replaces the legacy pattern of manually creating a type conforming to (for example) `EnvironmentKey` with a `defaultValue`, then extending `EnvironmentValues` with a computed property.
- Strongly prefer `overlay(alignment:content:)` over the deprecated `overlay(_:alignment:)`. For example, use `.overlay { Text("Hello, world!") }` rather than `.overlay(Text("Hello, world!"))`.
- Never use `.navigationBarLeading` and `.navigationBarTrailing` for toolbar item placement; they are deprecated. The correct, modern placements are `.topBarLeading` and `.topBarTrailing`.
- Prefer to rely on automatic grammar agreement when dealing with English, French, German, Portuguese, Spanish, and Italian. For example, use `Text("^[\(people) person](inflect: true)")` to show a number of people.
- You can fill and stroke a shape with two chained modifiers; you do *not* need an overlay for the stroke. The overlay was required previously, but this is fixed in iOS 17 and later.
- When referencing images from an asset catalog, prefer the generated symbol asset API when the project is configured to use them: `Image(.avatar)` rather than `Image("avatar")`.
- When targeting iOS 26 and later, SwiftUI has a native `WebView` view type that replaces almost all uses of hand-wrapped `WKWebView` inside `UIViewRepresentable`. To use it, make sure to include `import WebKit`.
- `ForEach` over an `enumerated()` sequence should not convert to an array first. Use `ForEach(items.enumerated(), id: \.element.id)` directly.
- When hiding scroll indicators, use `.scrollIndicators(.hidden)` rather than `showsIndicators: false` in the initializer.
- Never use `Text` concatenation with `+`.

For example, the usage of `+` here is bad and deprecated:

```swift
Text("Hello").foregroundStyle(.red)
+
Text("World").foregroundStyle(.blue)
```

Instead, use text interpolation like this:

```swift
let red = Text("Hello").foregroundStyle(.red)
let blue = Text("World").foregroundStyle(.blue)
Text("\(red)\(blue)")
```


## Using ObservableObject

If using `ObservableObject` is absolutely required – for example if you are trying to create a debouncer using a Combine publisher – you should always make sure `import Combine` is added. This was previously provided through SwiftUI, but that is no longer the case.
