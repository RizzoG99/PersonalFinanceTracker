import Testing
import SwiftUI
import UIKit
@testable import PersonalFinanceTraker

/// Guards the curated icon / color catalog behind the category pickers (#177).
struct CategoryCatalogTests {

    private let appBundle = Bundle(for: BackupService.self)

    // MARK: - Icons

    @Test func symbolsAreUniqueAcrossGroups() {
        let names = CategoryConstants.symbolNames
        #expect(Set(names).count == names.count)
        #expect(CategoryConstants.symbolGroups.allSatisfy { !$0.symbols.isEmpty })
    }

    @Test func everySymbolExistsOnThisOS() {
        let missing = CategoryConstants.symbolNames.filter { UIImage(systemName: $0) == nil }
        #expect(missing.isEmpty, "Unknown SF Symbols: \(missing)")
    }

    @Test func catalogOffersAMotorcycle() {
        #expect(CategoryConstants.symbolNames.contains("motorcycle.fill"))
    }

    @Test func unfilledSeededSymbolsShareTheFilledLabel() {
        #expect(CategoryConstants.symbolLabel("cart") == CategoryConstants.symbolLabel("cart.fill"))
        #expect(CategoryConstants.symbolLabel("house") == CategoryConstants.symbolLabel("house.fill"))
    }

    @Test func swappedOutlineSymbolsShareTheFilledLabel() {
        #expect(CategoryConstants.symbolLabel("bicycle") == CategoryConstants.symbolLabel("bicycle.circle.fill"))
        #expect(CategoryConstants.symbolLabel("chart.line.uptrend.xyaxis")
                == CategoryConstants.symbolLabel("chart.line.uptrend.xyaxis.circle.fill"))
    }

    @Test func symbolOutsideTheCatalogGetsAGenericLabelNotItsIdentifier() {
        #expect(CategoryConstants.symbolLabel("globe") != "globe")
    }

    // MARK: - Saved categories keep working

    /// Every icon and color the pickers offered before #177. Users saved categories with these,
    /// so dropping one would make a stored choice vanish from the picker (colors would fall
    /// back to indigo through `Color(categoryToken:)`).
    private static let preCatalogSymbols = [
        "cart.fill", "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
        "birthday.cake.fill", "wineglass.fill", "car.fill", "fuelpump.fill", "bus.fill", "tram.fill",
        "bicycle", "airplane", "house.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi", "phone.fill",
        "bag.fill", "tshirt.fill", "sparkles", "tag.fill", "cross.case.fill", "heart.fill", "figure.run",
        "dumbbell.fill", "pills.fill", "film.fill", "music.note", "gamecontroller.fill",
        "books.vertical.fill", "paintbrush.fill", "banknote.fill", "chart.line.uptrend.xyaxis",
        "creditcard.fill", "building.columns.fill", "laptopcomputer", "briefcase.fill",
        "graduationcap.fill", "pencil", "suitcase.fill", "pawprint.fill", "leaf.fill", "sun.max.fill",
        "gift.fill", "star.fill", "person.fill", "ellipsis.circle.fill"
    ]
    private static let preCatalogTokens = [
        "categoryIndigo", "categoryGreen", "categoryAmber", "categoryPink",
        "categoryPurple", "categoryTeal", "categoryGray"
    ]

    /// A symbol may be swapped for its filled sibling (`bicycle` → `bicycle.circle.fill`), but a
    /// category that still stores the old one must keep a readable name in the Edit sheet.
    @Test func everySymbolOfferedBeforeIsStillInTheCatalogOrNamedAsItsSuccessor() {
        #expect(Self.preCatalogSymbols.count == 48)
        let generic = CategoryConstants.symbolLabel("no.such.symbol")
        let unnamed = Self.preCatalogSymbols.filter {
            !CategoryConstants.symbolNames.contains($0) && CategoryConstants.symbolLabel($0) == generic
        }
        #expect(unnamed.isEmpty, "Saved with these, but now shown as 'Current icon': \(unnamed)")
    }

    @Test func catalogKeepsEveryColorOfferedBefore() {
        let dropped = Self.preCatalogTokens.filter { !CategoryConstants.colorTokenNames.contains($0) }
        #expect(dropped.isEmpty, "Removed from the picker: \(dropped)")
        // A kept token must resolve to itself, not to the indigo fallback.
        let fallback = Color(categoryToken: "no-such-token")
        for token in Self.preCatalogTokens where token != "categoryIndigo" {
            #expect(Color(categoryToken: token) != fallback)
        }
    }

    // MARK: - Colors

    @Test func everyColorTokenIsAnAdaptiveAsset() {
        let tokens = CategoryConstants.colorTokenNames
        #expect(Set(tokens).count == tokens.count)
        for token in tokens {
            let light = resolved(token, .light)
            let dark = resolved(token, .dark)
            #expect(light != nil, "\(token) has no light variant in the asset catalog")
            #expect(dark != nil, "\(token) has no dark variant in the asset catalog")
            #expect(light != dark, "\(token) is not adaptive")
        }
    }

    @Test func safeLookupResolvesEveryTokenWithoutFallingBack() {
        let fallback = Color(categoryToken: "no-such-token")
        for token in CategoryConstants.colorTokenNames where token != "categoryIndigo" {
            #expect(Color(categoryToken: token) != fallback, "\(token) fell back to indigo")
        }
    }

    // MARK: - Localized names (VoiceOver)

    @Test(arguments: ["en", "it"])
    func everyIconColorAndGroupHasAHumanReadableName(language: String) {
        let keys = CategoryConstants.symbolNames
            + CategoryConstants.colorTokenNames
            + CategoryConstants.symbolGroups.map(\.titleKey)
        let missing = keys.filter { translation(for: $0, language: language) == nil }
        #expect(missing.isEmpty, "No \(language) name for: \(missing)")
    }

    // MARK: - Name collisions

    /// The reason the picker names have their own table: a category the user (or a CSV import)
    /// called "wifi" must keep that name, not turn into "Internet".
    @Test(arguments: ["wifi.circle.fill", "categoryRed", "iconGroup.food", "cart.fill"])
    func pickerKeysNeverTranslateACategoryName(key: String) {
        #expect(key.localizedCategoryDisplay == key)
    }

    @Test func pickerKeysAreNotInTheMainCatalog() {
        let keys = CategoryConstants.symbolNames
            + CategoryConstants.colorTokenNames
            + CategoryConstants.symbolGroups.map(\.titleKey)
        for language in ["en", "it"] {
            let leaked = keys.filter { translation(for: $0, language: language, table: nil) != nil }
            #expect(leaked.isEmpty, "Also in Localizable (\(language)): \(leaked)")
        }
    }

    // MARK: - Helpers

    private func resolved(_ token: String, _ style: UIUserInterfaceStyle) -> [CGFloat]? {
        guard let color = UIColor(named: token, in: appBundle, compatibleWith: UITraitCollection(userInterfaceStyle: style))
        else { return nil }
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    /// Reads the compiled `<language>.lproj` directly, so the check doesn't depend on the
    /// test process's own language.
    private func translation(for key: String, language: String, table: String? = CategoryConstants.catalogTable) -> String? {
        guard let path = appBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let sentinel = "\u{1F6AB}missing"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: table)
        return value == sentinel || value.isEmpty ? nil : value
    }
}
