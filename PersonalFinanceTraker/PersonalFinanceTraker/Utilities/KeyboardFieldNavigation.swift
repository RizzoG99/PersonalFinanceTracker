import SwiftUI

extension View {
    /// Adds the standard ‹ › / Done bar above the keyboard for moving between a form's text fields.
    ///
    /// Without it the only way off a field is dismissing the keyboard and scrolling to the next one —
    /// which in landscape means scrolling a form that has almost no room to scroll. The amount fields
    /// make it worse: a `decimalPad` has no Return key at all, so `submitLabel` can't help there.
    ///
    /// - Parameters:
    ///   - order: the fields in tab order. Typed fields only — chaining into a picker would
    ///     make Next look like it dismissed the keyboard for nothing.
    ///   - accessory: extra content on its own row below ‹ › Done, for form-specific controls
    ///     that only make sense while this particular keyboard is up. Empty by default so
    ///     existing callers (e.g. AddGoalSheet) are unaffected.
    ///   - navigate: called instead of assigning `focus.wrappedValue` directly when set. Lets a
    ///     caller with a ScrollViewReader scroll the target field into view first and only
    ///     request focus once it's actually on screen — setting FocusState for a field whose row
    ///     is currently scrolled out of a Form/List isn't guaranteed to move first responder.
    ///     nil (default) keeps the old direct-assignment behavior.
    func keyboardFieldNavigation<Field: Hashable, Accessory: View>(
        _ focus: FocusState<Field?>.Binding,
        order: [Field],
        hideDone: Bool = false,
        hideFocusButtons: Bool = false,
        navigate: ((Field) -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView().frame(maxWidth: .infinity) }
    ) -> some View {
        // A single ToolbarItem wrapping a VStack (not ToolbarItemGroup, whose children lay out
        // in one row) so the accessory content gets its own row under ‹ › Done instead of being
        // squeezed into the same line.
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack(alignment: .center) {
                    if (!hideFocusButtons) {
                        let index = focus.wrappedValue.flatMap { order.firstIndex(of: $0) }

                        Button {
                            if let index, index > 0 {
                                let target = order[index - 1]
                                if let navigate { navigate(target) } else { focus.wrappedValue = target }
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .accessibilityLabel("Previous field")
                        .disabled(index == nil || index == 0)
                        // Reported as unresponsive on-device (taps producing no effect at all) while
                        // the same button worked in the Simulator — a visual-position-vs-hit-region
                        // mismatch is the standard cause once `.sharedBackgroundVisibility(.hidden)`
                        // is in play (see below): the tap target can end up not matching where the
                        // glass capsule is actually drawn. Forcing the hit shape onto the rendered
                        // frame is the standard fix and is a no-op visually.
                        .contentShape(Rectangle())

                        Button {
                            if let index, index < order.count - 1 {
                                let target = order[index + 1]
                                if let navigate { navigate(target) } else { focus.wrappedValue = target }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .accessibilityLabel("Next field")
                        .disabled(index == nil || index == order.count - 1)
                        .contentShape(Rectangle())
                    }

                    Spacer()
                    accessory()
                    Spacer()

                    if (!hideDone) {
                        Button("Done") { focus.wrappedValue = nil }
                            .fontWeight(.semibold)
                            .contentShape(Rectangle())
                    }
                }
                // `.sharedBackgroundVisibility(.hidden)` below makes this item size to its
                // content's ideal width, not the full keyboard width — so a bare `.frame` on
                // this HStack had no effect (the item's own proposal was already capped before
                // the frame request could matter). What actually forces full width: the two
                // `Spacer()`s around `accessory()` above are unconditional (not nested inside
                // conditionally-shown content), and `accessory()` itself always contains
                // something genuinely flexible — either the default `.frame(maxWidth: .infinity)`
                // placeholder or a caller's own `.frame(maxWidth: .infinity)`-wrapped content
                // (see `TransactionFormView`). A `Spacer()` alone wasn't enough; a child that
                // actually requests infinite ideal width is what the layout responds to here.
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                // Glass only. A `.bar` background under it was tried as a fallback in case the
                // toolbar stripped the glass effect — it doesn't, and `.bar` is opaque enough
                // that it filled in the very translucency the glass is there to provide.
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
            }
            // The load-bearing line. iOS 26 reserves ~48pt of height for a keyboard toolbar
            // item and draws a shared glass background filling it, so the bar sits flush to
            // the keyboard and any padding just makes that background taller. Hiding it frees
            // the item to be smaller than its slot, which is what turns the padding above
            // into a real gap — and obliges us to bring our own background.
            .sharedBackgroundVisibility(.hidden)
        }
        // Scroll-avoidance (both the system's automatic kind and a manual
        // `ScrollViewReader.scrollTo(anchor: .top)`) only knows about that reserved ~48pt
        // slot — this bar's real height (padding + glass capsule + the 20pt bottom margin
        // above) is taller than that and isn't reflected back into the layout, so a field
        // scrolled to the top of the "avoided" area still ends up right behind this bar.
        // Reserving the difference here as extra safe area, only while the bar is actually
        // showing, is what makes `anchor: .top` land above the bar instead of above just
        // the raw keyboard.
        .safeAreaInset(edge: .bottom) {
            if focus.wrappedValue != nil {
                Color.clear.frame(height: 60)
            }
        }
    }
}
