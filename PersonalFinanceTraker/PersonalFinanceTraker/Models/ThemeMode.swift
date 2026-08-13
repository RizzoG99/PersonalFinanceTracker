import SwiftUI
import UIKit

/// The user's appearance preference. Persisted by raw value under the
/// `app_theme_mode` key — see `ProfileAppearanceSection`.
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    /// For `.preferredColorScheme`, which restyles the SwiftUI hierarchy itself —
    /// including system chrome such as `TabView`'s floating tab bar and
    /// `glassEffect` surfaces. `nil` means "follow the system".
    ///
    /// Applied together with ``uiStyle``; see that property for why one mechanism
    /// is not enough.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  nil
        case .light: .light
        case .dark:  .dark
        }
    }

    /// For the window's `overrideUserInterfaceStyle`, applied *alongside*
    /// ``colorScheme``. Neither mechanism covers the whole app on its own:
    ///
    /// - `.preferredColorScheme` is a preference that only reaches its own
    ///   presentation container, so a `.sheet` already on screen kept the
    ///   appearance it was created with — including the Settings sheet that
    ///   hosts the picker.
    /// - The window trait fixes those presented containers, but does not restyle
    ///   SwiftUI's own chrome: with it alone the floating tab bar and the glass
    ///   toolbar buttons stayed light after switching to dark.
    ///
    /// The two always carry the same value, so they cannot disagree.
    /// `.unspecified` means "follow the system".
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .auto:  .unspecified
        case .light: .light
        case .dark:  .dark
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .auto:  "Auto"
        case .light: "Light"
        case .dark:  "Dark"
        }
    }
}
