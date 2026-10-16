import Foundation
import Testing
@testable import PersonalFinanceTraker

struct AppIdentityTests {
    @Test func installedAppMatchesCompiledIdentity() throws {
        #if PFT_TEST_BUILD
        let bundleID = "rizzoG99.PersonalFinanceTraker.test"
        let displayName = "PFT TEST"
        #else
        let bundleID = "rizzoG99.PersonalFinanceTraker"
        let displayName = "Personal Finance"
        #endif
        #expect(Bundle.main.bundleIdentifier == bundleID)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == displayName)
        #expect(AppGroup.identifier == "group.\(bundleID)")
        #expect(HabitWidgetSnapshotStore.appGroupIdentifier == AppGroup.identifier)
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == [AppIdentity.urlScheme])
        #if PFT_TEST_BUILD
        #expect(!schemes.contains("personalfinancetraker"))
        #else
        #expect(schemes == ["personalfinancetraker"])
        #endif
    }

    @Test @MainActor func persistentStoreBelongsToThisInstallation() throws {
        let group = try #require(FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ))
        let configuration = try #require(AppContainer.shared.configurations.first)
        let store = configuration.url.standardizedFileURL.path
        let allowedRoots = [group, URL(fileURLWithPath: NSHomeDirectory())]
        #expect(allowedRoots.contains { store.hasPrefix($0.standardizedFileURL.path + "/") })
        #expect(AppContainer.containerCreationError == nil)
    }
}
