//
//  ImportProfileStoreTests.swift
//  PersonalFinanceTrakerTests
//

import Foundation
import Testing
@testable import PersonalFinanceTraker

struct ImportProfileStoreTests {

    private func freshStore() -> ImportProfileStore {
        ImportProfileStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test func signatureIsStableForSameHeaders() {
        let a = ImportProfileStore.signature(headers: ["Date", "Amount", "Note"], delimiter: ";")
        let b = ImportProfileStore.signature(headers: ["Date", "Amount", "Note"], delimiter: ";")
        #expect(a == b)
    }

    @Test func signatureDiffersForDifferentHeadersOrDelimiter() {
        let base = ImportProfileStore.signature(headers: ["Date", "Amount"], delimiter: ";")
        #expect(base != ImportProfileStore.signature(headers: ["Date", "Importo"], delimiter: ";"))
        #expect(base != ImportProfileStore.signature(headers: ["Date", "Amount"], delimiter: ","))
    }

    @Test func saveAndLoadRoundTrip() {
        let store = freshStore()
        var mapping = ColumnMapping()
        mapping.dateColumn = "Date"
        mapping.amountColumn = "Amount"
        mapping.dateFormat = "dd/MM/yyyy"
        mapping.signConvention = .allExpenses
        let profile = ImportProfile(
            mapping: mapping,
            categorySelections: ["🍕 Food": UUID().uuidString]
        )
        let sig = ImportProfileStore.signature(headers: ["Date", "Amount"], delimiter: ";")

        store.save(profile, for: sig)

        #expect(store.profile(for: sig) == profile)
        #expect(store.profile(for: "other") == nil)
    }

    @Test func savingAgainOverwrites() {
        let store = freshStore()
        let sig = ImportProfileStore.signature(headers: ["Date"], delimiter: ",")
        var mapping = ColumnMapping()
        mapping.dateColumn = "Date"
        store.save(ImportProfile(mapping: mapping, categorySelections: [:]), for: sig)
        mapping.dateFormat = "yyyy-MM-dd"
        let updated = ImportProfile(mapping: mapping, categorySelections: ["A": "B"])
        store.save(updated, for: sig)
        #expect(store.profile(for: sig) == updated)
    }
}
