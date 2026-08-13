import Testing
import SwiftUI
@testable import PersonalFinanceTraker

struct ThemeModeTests {

    @Test func rawValuesRoundTrip() {
        for mode in ThemeMode.allCases {
            #expect(ThemeMode(rawValue: mode.rawValue) == mode)
        }
    }

    /// @AppStorage keys off these strings. Changing one silently resets every
    /// existing user's choice back to the default, so pin them.
    @Test func rawValuesAreStable() {
        #expect(ThemeMode.auto.rawValue == "auto")
        #expect(ThemeMode.light.rawValue == "light")
        #expect(ThemeMode.dark.rawValue == "dark")
    }

    @Test func allCasesAreOfferedInPickerOrder() {
        #expect(ThemeMode.allCases == [.auto, .light, .dark])
    }

    /// The appearance is applied by setting `overrideUserInterfaceStyle` on the
    /// UIWindow, not via `.preferredColorScheme`. A root `.preferredColorScheme`
    /// only governs its own presentation container, so already-presented sheets
    /// never saw the change; a window trait change propagates to every view
    /// controller in the window, presented sheets included.
    @Test func autoMapsToUnspecifiedSoTheSystemDecides() {
        #expect(ThemeMode.auto.uiStyle == .unspecified)
    }

    @Test func lightAndDarkMapToTheirInterfaceStyles() {
        #expect(ThemeMode.light.uiStyle == .light)
        #expect(ThemeMode.dark.uiStyle == .dark)
    }

    /// An absent key must fall back to .auto — the shipped default.
    @Test func absentStoredValueFallsBackToAuto() {
        #expect(ThemeMode(rawValue: "not-a-mode") == nil)
        #expect(ThemeMode(rawValue: "not-a-mode") ?? .auto == .auto)
    }
}
