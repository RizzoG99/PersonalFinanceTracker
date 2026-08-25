import Testing
@testable import PersonalFinanceTraker

struct CategoryNameValidatorTests {
    @Test("Accepts CSV-compatible category names with common punctuation")
    func acceptsCommonPunctuation() {
        #expect(CategoryNameValidator.isValid("Photography & Videomaking"))
        #expect(CategoryNameValidator.isValid("Rent/Mortgage"))
        #expect(CategoryNameValidator.isValid("Kids' Activities - Summer"))
        #expect(CategoryNameValidator.isValid("Caffè, Bar (Downtown)"))
    }

    @Test("Rejects unsupported category characters")
    func rejectsUnsupportedCharacters() {
        #expect(!CategoryNameValidator.isValid("Food < Groceries"))
        #expect(!CategoryNameValidator.isValid("Bills @ Home"))
    }
}
