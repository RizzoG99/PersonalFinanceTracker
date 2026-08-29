//
//  ReceiptCategoryMap.swift
//  PersonalFinanceTraker
//
//  The user's own answer to "which of my categories is eating out?".
//
//  Every other tier in `ReceiptCategoryInferrer` ends by matching a canonical concept against the
//  *names* of the user's categories, through a fixed synonym list in `CategoryAutoMapper`. That
//  works only for someone whose categories happen to be named in one of the five languages that
//  list covers. Categories are user-created and user-renamed: "Uscite varie", "Gelati", a Polish or
//  Portuguese name, or simply "Fun" all identify a real category that no synonym reaches. Apple
//  Maps can name the shop perfectly and the answer still lands nowhere.
//
//  So this stores an explicit concept → category pairing the user sets once. It is consulted before
//  any name matching, and is the only tier that cannot be wrong about what the user meant.
//
//  Stored in `UserDefaults` rather than SwiftData: it is a handful of settings, it follows the same
//  pattern as `app_base_currency`, and it needs no schema. Category *ids* are stored, so renaming a
//  category keeps its mapping — which is the whole point.
//

import Foundation

/// A spending concept a receipt can be recognized as, independent of what the user calls it.
/// Raw values are the canonical keywords `CategoryAutoMapper` already uses, so a keyword coming out
/// of the local table or an Apple Maps POI maps straight onto one of these.
enum ReceiptCategoryConcept: String, CaseIterable, Identifiable, Sendable {
    case restaurant, grocer, transport, travel, shopping
    case health, fitness, beauty, entertain
    case edu, house, util, pet, gift

    var id: String { rawValue }

    /// Shown in Settings. Deliberately concrete ("Eating out", not "Restaurant") — the user is
    /// answering "which of my categories does a receipt like this belong to".
    var title: LocalizedStringResource {
        switch self {
        case .restaurant: "Eating out"
        case .grocer: "Groceries"
        case .transport: "Transport & fuel"
        case .travel: "Travel"
        case .shopping: "Shopping"
        case .health: "Health & pharmacy"
        case .fitness: "Fitness"
        case .beauty: "Beauty & wellbeing"
        case .entertain: "Entertainment"
        case .edu: "Education"
        case .house: "Home"
        case .util: "Bills"
        case .pet: "Pets"
        case .gift: "Gifts"
        }
    }

    var systemImage: String {
        switch self {
        case .restaurant: "fork.knife"
        case .grocer: "cart"
        case .transport: "fuelpump"
        case .travel: "airplane"
        case .shopping: "bag"
        case .health: "cross.case"
        case .fitness: "figure.run"
        case .beauty: "sparkles"
        case .entertain: "theatermasks"
        case .edu: "book"
        case .house: "house"
        case .util: "bolt"
        case .pet: "pawprint"
        case .gift: "gift"
        }
    }
}

enum ReceiptCategoryMap {
    private static let defaultsKey = "receiptCategoryConcepts"

    /// concept raw value → category `UUID` string.
    private static var stored: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static func categoryId(for concept: ReceiptCategoryConcept) -> UUID? {
        stored[concept.rawValue].flatMap(UUID.init(uuidString:))
    }

    static func setCategoryId(_ id: UUID?, for concept: ReceiptCategoryConcept) {
        var map = stored
        map[concept.rawValue] = id?.uuidString
        stored = map
    }

    /// The category the user picked for whichever concept this keyword belongs to, if any.
    /// `keyword` is whatever a tier produced — "ristorante", "benzina", an Apple Maps-derived word.
    static func category(forKeyword keyword: String, in pool: [CategorySnapshot]) -> CategorySnapshot? {
        guard let concept = CategoryAutoMapper.canonicalConcept(for: keyword),
              let mapped = ReceiptCategoryConcept(rawValue: concept),
              let id = categoryId(for: mapped)
        else { return nil }
        return pool.first { $0.id == id }
    }

    /// Drops pairings whose category no longer exists, so a deleted category does not leave a
    /// mapping that silently matches nothing.
    static func prune(against categories: [CategorySnapshot]) {
        let live = Set(categories.map(\.id.uuidString))
        stored = stored.filter { live.contains($0.value) }
    }
}
