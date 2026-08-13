import SwiftUI
import UIKit

/// The user's appearance preference. Persisted by raw value under the
/// `app_theme_mode` key — see `ProfileAppearanceSection`.
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    /// Applied to the window's `overrideUserInterfaceStyle` rather than through
    /// `.preferredColorScheme`.
    ///
    /// `.preferredColorScheme` is a preference that only reaches its own
    /// presentation container. A `.sheet` is a separate presentation, so a sheet
    /// that was already on screen kept the appearance it was created with and the
    /// Settings sheet — which contains the picker itself — visibly failed to
    /// follow the switch. Changing the window's trait collection instead
    /// propagates to every view controller in that window, presented sheets
    /// included, and SwiftUI's `\.colorScheme` environment derives from the same
    /// traits, so `AppBackground` still reacts.
    ///
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
