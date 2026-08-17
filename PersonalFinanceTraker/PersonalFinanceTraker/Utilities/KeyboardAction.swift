//
//  KeyboardAction.swift
//  PersonalFinanceTraker
//

import SwiftUI

extension View {
    /// Attaches a keyboard shortcut that has no on-screen control of its own.
    ///
    /// ponytail: iPadOS builds its ⌘-hold overlay from every live `keyboardShortcut` in the
    /// responder chain, visible or not — so a zero-size button is the entire implementation.
    /// The alternative, `commands()` + `FocusedValues`, would mean lifting the shell's state up
    /// to the `App` scene just to reach it from a menu that iPad doesn't have a menu bar for.
    /// Revisit when Mac lands and a real menu bar is worth the plumbing.
    func keyboardAction(
        _ key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        background {
            Button(title, action: action)
                .keyboardShortcut(key, modifiers: modifiers)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
