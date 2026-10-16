import Foundation

/// Shared by the app and both widget extensions. TEST builds must never open the
/// production app's shared container or send widget actions to its URL scheme.
enum AppIdentity {
    #if PFT_TEST_BUILD
    static let appGroupIdentifier = "group.rizzoG99.PersonalFinanceTraker.test"
    static let urlScheme = "personalfinancetraker-test"
    #else
    static let appGroupIdentifier = "group.rizzoG99.PersonalFinanceTraker"
    static let urlScheme = "personalfinancetraker"
    #endif
}
