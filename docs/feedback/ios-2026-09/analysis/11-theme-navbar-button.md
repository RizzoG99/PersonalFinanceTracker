# Navigation Bar Close Button Theme Update Bug — Build 54 iOS 26.6

**Date**: 2026-09-22  
**Severity**: P2  
**Status**: Root cause identified

---

## Symptom

When the user changes the app theme (light ↔ dark) while a settings sheet is open, the close button (X) on the sheet's navigation bar does not update its color to match the new theme. The button remains in the old theme's colors.

**Workaround**: Close the sheet and reopen it — the close button renders correctly in the new theme.

**Context**: Screenshot shows Settings sheet in dark mode with light-colored close button. Bug occurs when user taps theme selector while this sheet is already visible.

---

## Root cause

Two related issues interact:

### Issue 1: NavigationStack close button captured at presentation time

**Location**: `PersonalFinanceTraker/PersonalFinanceTraker/Features/CategoryBreakdown/CategoryBreakdownView.swift:122-128`

```swift
.sheet(isPresented: $showingSettings) {
    NavigationStack {
        CategorySettingsView()
    }
    .environment(\.modelContext, modelContext)
    .presentationBackground { AppBackground() }
}
```

When SwiftUI's `NavigationStack` is presented inside a `.sheet()`, the system renders a close button (X) in the navigation bar as part of the presentation styling. This close button's appearance is determined at the moment the sheet is presented. It reads the current `preferredColorScheme` from the environment at that time.

### Issue 2: preferredColorScheme only affects new presentations

**Location**: `PersonalFinanceTraker/PersonalFinanceTraker/Models/ThemeMode.swift:31-36`

```swift
/// `.preferredColorScheme` is a preference that only reaches its own
/// presentation container, so a `.sheet` already on screen kept the
/// appearance it was created with — including the Settings sheet that
/// hosts the picker.
```

And applied in: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift:56`

```swift
.preferredColorScheme(themeMode.colorScheme)
```

The `.preferredColorScheme` modifier in the app's root only reaches containers created *after* the value changes. For an already-presented sheet, the NavigationStack's navigation bar chrome (including the close button) was styled when the sheet was created and does not automatically re-render when `.preferredColorScheme` changes.

### Issue 3: Window override doesn't reliably reach NavigationStack chrome

**Location**: `PersonalFinanceTraker/PersonalFinanceTraker/App/PersonalFinanceTrakerApp.swift:101-122` — the `applyAppearance` function

```swift
func applyAppearance(_ mode: ThemeMode) {
    for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        let resolvedForPresented: UIUserInterfaceStyle =
            mode == .auto ? windowScene.traitCollection.userInterfaceStyle : mode.uiStyle
        for window in windowScene.windows {
            window.overrideUserInterfaceStyle = mode.uiStyle
            var presented = window.rootViewController?.presentedViewController
            while let controller = presented {
                controller.overrideUserInterfaceStyle = resolvedForPresented
                presented = controller.presentedViewController
            }
        }
    }
}
```

This code sets `overrideUserInterfaceStyle` on the window and traverses the `presentedViewController` chain. However, for a SwiftUI sheet containing a NavigationStack, the hierarchy is:

- `UIWindow`
- `UIPresentationViewController` (the sheet container)
  - `UIHostingController` (SwiftUI content)

The close button is rendered by the system at the presentation layer *before* the `UIHostingController` is reached. Setting `overrideUserInterfaceStyle` on the `UIHostingController` inside the sheet does not force the already-rendered system chrome (close button) to re-render, because the presentation styling was already applied at a higher layer.

---

## Edge cases

1. **Multiple nested sheets**: If one sheet presents another sheet, and the user changes theme while the inner sheet is visible, both sheets' close buttons may fail to update until dismissed.

2. **Other presentation styles**: `.fullScreenCover()` would likely have the same issue, as it also creates system chrome at the presentation layer.

3. **NavigationStack on main view**: A NavigationStack on the main app window (not inside a sheet) updates correctly because `.preferredColorScheme` reaches it before it's presented.

---

## Priority confirmation

**P2 correct.**

Rationale:
- **User-visible and affects core settings workflow** — Settings is accessed frequently
- **Complete workaround exists** — close and reopen the sheet
- **Does not block functionality** — users can still interact with and dismiss the sheet (the dismiss gesture works even if the button color is wrong)
- **Isolated to presentation chrome** — the sheet's content and controls update correctly; only the system-rendered close button fails

---

## Open Points

1. **Why doesn't the window override force a re-render of the presentation chrome?** The `overrideUserInterfaceStyle` is set on the window and all presented controllers, but the navigation bar's close button (rendered by UIKit at the presentation layer) does not refresh. Is this a UIKit limitation, or is there a missing invalidation call to force re-layout of the presentation container?

2. **Does `preferredColorScheme` have an onChange handler that could force re-resolution of navigation chrome?** Could a `.onChange(of: preferredColorScheme)` trigger a refresh?

3. **Is the presented view controller chain being traversed completely?** For a NavigationStack inside a sheet, are there additional intermediate view controllers not reachable via `presentedViewController`?

---

## Suggested fix

### Option 1: Force presentation refresh via Environment observer (safest)

Add a view modifier or custom modifier to NavigationStack that re-renders when the preferredColorScheme changes. This would re-create the navigation chrome with the new scheme:

**Pros**: 
- No UIKit-level manipulation needed
- SwiftUI-native approach
- Isolated to the NavigationStack

**Cons**: 
- Requires modifying every `.sheet()` that contains a NavigationStack
- May cause brief visual flicker during re-render

### Option 2: Set preferredColorScheme on the sheet content before presentation

Apply `.preferredColorScheme()` directly on the NavigationStack inside the sheet (redundant with app-level, but ensures it's set):

```swift
.sheet(isPresented: $showingSettings) {
    NavigationStack {
        CategorySettingsView()
    }
    .preferredColorScheme(themeMode.colorScheme)  // explicitly propagate
    .environment(\.modelContext, modelContext)
    .presentationBackground { AppBackground() }
}
```

**Pros**: 
- Minimal code change
- No additional invalidation logic

**Cons**: 
- Doesn't solve the core issue (the modifier only affects newly-created views)
- May still not update chrome that was already rendered

### Option 3: Invalidate the presentation layer on theme change

Enhance `applyAppearance()` to explicitly invalidate the sheet's presentation controller after setting overrides:

```swift
if let sheetPresentationController = controller.sheetPresentationController {
    sheetPresentationController.invalidateDetents()
    // or: controller.view.setNeedsDisplay()
}
```

**Pros**: 
- Targets the actual problem layer (sheet presentation)
- Single fix at app level

**Cons**: 
- Requires testing on multiple iOS versions
- May have unintended side effects on sheet sizing/layout

### Option 4: Re-present the sheet on theme change (nuclear)

Listen for theme changes and dismiss/re-present sheets automatically:

**Pros**: 
- Guarantees fresh rendering with correct colors

**Cons**: 
- Disruptive UX (user loses sheet scroll position, form state)
- Complex coordination across multiple sheet states

---

## Recommended approach

**Option 1** is the cleanest: create a custom view modifier that wraps NavigationStack and explicitly observes theme changes, triggering a refresh. This keeps the fix localized and avoids UIKit complexity.

Alternatively, **Option 3** (invalidating the presentation layer) may work if UIKit provides a reliable API for it — test on iOS 26.0+ to confirm.

