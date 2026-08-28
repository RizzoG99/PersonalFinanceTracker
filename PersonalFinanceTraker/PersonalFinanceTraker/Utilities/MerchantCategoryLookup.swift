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
    private static let categoryKeywords: [MKPointOfInterestCategory: String] = [
        .restaurant: "ristorante",
        .cafe: "bar",
        .nightlife: "bar",
        .bakery: "spesa",
        .foodMarket: "spesa",
        .gasStation: "benzina",
        .pharmacy: "farmacia",
        .fitnessCenter: "palestra",
        .hotel: "hotel",
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
