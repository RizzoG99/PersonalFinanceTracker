import Testing
import SwiftUI
@testable import PersonalFinanceTraker

struct ThemeModeTests {

    @Test func autoMapsToNilSoTheSystemDecides() {
        #expect(ThemeMode.auto.colorScheme == nil)
    }

    @Test func lightAndDarkMapToTheirColorSchemes() {
        #expect(ThemeMode.light.colorScheme == .light)
        #expect(ThemeMode.dark.colorScheme == .dark)
    }

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

    /// An absent key must fall back to .auto — the shipped default.
    @Test func absentStoredValueFallsBackToAuto() {
        #expect(ThemeMode(rawValue: "not-a-mode") == nil)
        #expect(ThemeMode(rawValue: "not-a-mode") ?? .auto == .auto)
    }
}
