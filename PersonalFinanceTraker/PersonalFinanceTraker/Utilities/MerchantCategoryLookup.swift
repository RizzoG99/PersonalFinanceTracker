//
//  MerchantCategoryLookup.swift
//  PersonalFinanceTraker
//
//  Bridges a merchant's Apple Maps point-of-interest category to one of the canonical keywords
//  `CategoryAutoMapper` already knows — for merchants `ReceiptCategoryInferrer`'s local keyword
//  table doesn't recognize by name (e.g. "Barrueco S.R.L.", a restaurant with no generic word in
//  its name). Geocodes the *receipt's own printed address*, never the device's location, so this
//  needs no location permission — just network access, which a scan already implicitly allows by
//  running Vision on-device and then, only at this last resort, reaching out to Maps.
//
//  Best-effort only: any failure (no address on the receipt, offline, no match, an unrecognized
//  category) returns nil and the caller falls back to its own next tier. See
//  docs/features/2026-08-27-scan-receipt-autofill.md.
//

import MapKit

enum MerchantCategoryLookup {
    /// Small on purpose, same spirit as `ReceiptCategoryInferrer.merchantKeywords`: only the
    /// categories a personal-finance category set is likely to already have a match for.
    /// Apple Maps POI category → a canonical keyword `CategoryAutoMapper` already resolves against
    /// the user's own category names.
    ///
    /// Deliberately broad now. It started as nine entries covering the obvious cases, and the gaps
    /// were doing real damage: an unmapped category returns nil exactly like "no match at all", so
    /// the caller drops through to its last-resort tier and fills a *required* field with the
    /// user's most-used category. On a real device that turned a €5 gelato into "Banking Fees".
    /// A rough-but-present mapping is strictly better than a missing one, because the fallback it
    /// replaces carries no information about this receipt whatsoever.
    ///
    /// There is no ice-cream POI category in the SDK — a gelateria comes back as `.cafe`, `.bakery`
    /// or `.store` — which is why those three matter more than they look.
    private static let categoryKeywords: [MKPointOfInterestCategory: String] = [
        // Eating and drinking out.
        .restaurant: "ristorante", .cafe: "bar", .nightlife: "bar",
        .brewery: "bar", .distillery: "bar", .winery: "bar",
        // Food to take home. `.bakery` sits here rather than with the cafés because an Italian
        // panificio is a grocery run far more often than a sit-down.
        .bakery: "spesa", .foodMarket: "spesa",
        // Getting around.
        .gasStation: "benzina", .evCharger: "benzina", .parking: "trasporto",
        .publicTransport: "trasporto", .carRental: "trasporto", .automotiveRepair: "auto",
        // Health and wellbeing.
        .pharmacy: "farmacia", .hospital: "medico", .animalService: "veterinario",
        .fitnessCenter: "palestra", .spa: "benessere", .beauty: "bellezza",
        // Travel.
        .hotel: "hotel", .campground: "viaggio", .rvPark: "viaggio", .airport: "viaggio",
        .marina: "viaggio",
        // Going out. Museums and landmarks are leisure spending, not education.
        .movieTheater: "cinema", .theater: "teatro", .musicVenue: "intrattenimento",
        .museum: "intrattenimento", .aquarium: "intrattenimento", .zoo: "intrattenimento",
        .amusementPark: "intrattenimento", .nationalPark: "intrattenimento",
        .park: "intrattenimento", .landmark: "intrattenimento", .castle: "intrattenimento",
        .fortress: "intrattenimento", .planetarium: "intrattenimento", .stadium: "intrattenimento",
        .bowling: "intrattenimento", .miniGolf: "intrattenimento", .goKart: "intrattenimento",
        .skatePark: "sport", .golf: "sport", .tennis: "sport", .soccer: "sport",
        .basketball: "sport", .baseball: "sport", .volleyball: "sport", .swimming: "sport",
        .skating: "sport", .skiing: "sport", .surfing: "sport", .kayaking: "sport",
        .rockClimbing: "sport", .hiking: "sport", .fishing: "sport",
        // Learning.
        .school: "scuola", .university: "università", .library: "libri",
        // Everyday services and the generic shop, which is what a merchant Maps knows but cannot
        // classify comes back as.
        .store: "acquisti", .laundry: "casa", .bank: "altro", .atm: "altro", .postOffice: "altro",
    ]

    static func lookupKeyword(merchant: String, address: String?) async -> String? {
        // MKGeocodingRequest replaces the now-deprecated CLGeocoder in this same iOS 26 SDK —
        // confirmed against MapKit/MKGeocodingRequest.h directly rather than guessed: a failable
        // init, and `getMapItemsWithCompletionHandler:` bridges to an async `mapItems` getter.
        guard let address,
              let geocodingRequest = MKGeocodingRequest(addressString: address),
              let location = try? await geocodingRequest.mapItems.first?.location
        else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = merchant
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )

        guard let response = try? await MKLocalSearch(request: request).start(),
              let category = response.mapItems.first?.pointOfInterestCategory
        else { return nil }
        return categoryKeywords[category]
    }
}
