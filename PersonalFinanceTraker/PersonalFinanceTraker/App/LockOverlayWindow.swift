//
//  LockOverlayWindow.swift
//  PersonalFinanceTraker
//

import SwiftUI
import UIKit

/// Hosts the PIN lock screen / privacy cover in their own `UIWindow`, above the app's main
/// window, instead of as a SwiftUI sibling of the app shell.
///
/// A `.sheet`/`.fullScreenCover` is a UIKit modal presentation owned by the *presenting* window's
/// root view controller — nothing drawn inside that same root's own view hierarchy can render on
/// top of it, and SwiftUI `zIndex` has no meaning across that boundary. Putting the lock screen in
/// a higher-level window sidesteps the problem entirely: the app shell (and anything it has
/// presented, like an open Add Transaction sheet) never needs to be torn down to hide it.
///
/// Owned as `@State` by `AuthenticationWrapper`, which is never torn down while the app runs.
@MainActor
final class LockOverlayWindow {
    private var window: UIWindow?
    // Kept alive and reused across calls — see `show()`'s comment on why swapping `rootView` in
    // place (instead of replacing `window.rootViewController`) is what actually removed the flash.
    private var hosting: UIHostingController<AnyView>?

    /// Presents `content` full-screen above everything else, including UIKit modals.
    /// - Parameter interactive: `false` for the privacy cover (nothing to tap), `true` for the PIN
    ///   screen. `content()` is still called fresh every time — a fresh view (and, for the PIN
    ///   screen, a fresh view model) means no stale state carried over from the last lock — but it
    ///   now replaces the *existing* hosting controller's `rootView` instead of swapping in a brand
    ///   new `UIViewController` via `window.rootViewController`. Re-parenting the root view
    ///   controller forces a full view-controller-lifecycle + first-layout pass on every call,
    ///   which is what produced ~600ms of blank window (just the window's plain background color,
    ///   no content yet) on every lock/unlock cycle — reusing the hosting controller and letting
    ///   SwiftUI diff the new `rootView` in is effectively instant instead.
    func show(interactive: Bool, @ViewBuilder content: () -> some View) {
        // ponytail: single-window app — first connected scene is always the right one.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }

        let window = self.window ?? UIWindow(windowScene: scene)
        // Matches PersonalFinanceTrakerApp's UIWindow.appearance() base color: without it, a
        // freshly created UIWindow has no explicit background, so the first frame or two — before
        // the hosted SwiftUI content has actually laid out — shows through as a plain white/black
        // flash instead of the app's base color. Belt-and-suspenders with the appearance proxy
        // since this window is recreated on every cold launch, not just app startup.
        window.backgroundColor = UIColor(named: "LaunchBackground")

        if let hosting {
            hosting.rootView = AnyView(content())
        } else {
            let hosting = UIHostingController(rootView: AnyView(content()))
            hosting.view.backgroundColor = .clear
            window.rootViewController = hosting
            self.hosting = hosting
        }
        window.windowLevel = .alert + 1
        // Opaque content already blocks visual leakage; this additionally stops VoiceOver
        // from reaching the shell underneath while the overlay is up. Must be set on the
        // *window*, not the hosted view — `accessibilityViewIsModal` only excludes sibling
        // subtrees within the same window; cross-window exclusion needs the window itself
        // marked modal (verified: without this, the covered window's elements were still
        // showing up in the accessibility tree).
        window.accessibilityViewIsModal = true
        window.isUserInteractionEnabled = interactive
        window.isHidden = false
        self.window = window
    }

    func hide() {
        // Kept alive (not nil'd out): show() always builds a fresh hosting controller anyway
        // (see its doc comment), so there's nothing stale to worry about — but discarding the
        // window here meant *every* lock/unlock cycle, not just cold launch, paid the first-frame
        // window-creation race that caused the flash this file's other comment describes.
        window?.isHidden = true
    }
}
