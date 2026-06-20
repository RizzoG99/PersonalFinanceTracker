import Foundation

@Observable
final class AppSettings {
    var payCycleStartDay: Int {
        didSet { UserDefaults.standard.set(payCycleStartDay, forKey: "payCycleStartDay") }
    }

    init() {
        let v = UserDefaults.standard.integer(forKey: "payCycleStartDay")
        payCycleStartDay = v == 0 ? 1 : v
    }

    static var storedStartDay: Int {
        let v = UserDefaults.standard.integer(forKey: "payCycleStartDay")
        return v == 0 ? 1 : v
    }
}
