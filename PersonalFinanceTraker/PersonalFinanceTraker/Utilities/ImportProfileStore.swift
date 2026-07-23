//
//  ImportProfileStore.swift
//  PersonalFinanceTraker
//
//  Remembers column + category mappings per bank-file layout so re-importing
//  a monthly statement is prefilled. Stored in UserDefaults (not SwiftData)
//  on purpose: profiles survive Delete All Data and stay decoupled from the
//  model container.
//

import Foundation
import CryptoKit

struct ImportProfile: Codable, Equatable {
    var mapping: ColumnMapping
    var categorySelections: [String: String]  // CSV category name → CategoryModel UUID string
}

final class ImportProfileStore {
    // ponytail: UserDefaults JSON blob; move to SwiftData if profiles ever need syncing
    private let key = "importProfiles.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Layout fingerprint: header row + delimiter. Unit separator between
    /// headers so ["a,b"] and ["a","b"] can't collide.
    static func signature(headers: [String], delimiter: Character) -> String {
        let payload = headers.joined(separator: "\u{1F}") + "\u{1E}" + String(delimiter)
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func profile(for signature: String) -> ImportProfile? {
        all()[signature]
    }

    func save(_ profile: ImportProfile, for signature: String) {
        var profiles = all()
        profiles[signature] = profile
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: key)
        }
    }

    private func all() -> [String: ImportProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([String: ImportProfile].self, from: data)
        else { return [:] }
        return profiles
    }
}
