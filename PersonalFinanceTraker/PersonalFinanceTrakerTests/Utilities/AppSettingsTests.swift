import Testing
import Foundation
@testable import PersonalFinanceTraker

@MainActor
@Suite(.serialized)
struct AppSettingsTests {

    private func resetDefaults() {
        UserDefaults.standard.removeObject(forKey: "payCycleStartDay")
    }

    @Test func defaultsToOneWhenKeyAbsent() {
        resetDefaults()
        let settings = AppSettings()
        #expect(settings.payCycleStartDay == 1)
    }

    @Test func persistsToUserDefaults() {
        resetDefaults()
        let settings = AppSettings()
        settings.payCycleStartDay = 15
        let settings2 = AppSettings()
        #expect(settings2.payCycleStartDay == 15)
        resetDefaults()
    }

    @Test func storedStartDayDefaultsToOne() {
        resetDefaults()
        #expect(AppSettings.storedStartDay == 1)
    }

    @Test func storedStartDayReflectsStoredValue() {
        resetDefaults()
        UserDefaults.standard.set(20, forKey: "payCycleStartDay")
        #expect(AppSettings.storedStartDay == 20)
        resetDefaults()
    }

    @Test func clampsValueAbove28() {
        resetDefaults()
        let settings = AppSettings()
        settings.payCycleStartDay = 50
        #expect(settings.payCycleStartDay == 28)
        resetDefaults()
    }

    @Test func clampsValueBelow1() {
        resetDefaults()
        let settings = AppSettings()
        settings.payCycleStartDay = 0
        #expect(settings.payCycleStartDay == 1)
        resetDefaults()
    }
}
