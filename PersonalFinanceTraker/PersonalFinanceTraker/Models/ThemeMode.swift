import SwiftUI

/// The user's appearance preference. Persisted by raw value under the
/// `app_theme_mode` key — see `ProfileAppearanceSection`.
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    /// `nil` means "follow the system", which is what `.preferredColorScheme`
    /// interprets as no override.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  nil
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
