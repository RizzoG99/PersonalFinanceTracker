import Testing
@testable import PersonalFinanceTraker

struct PendingTransactionIntentTests {
    @Test func consumesFlagOnceWhenNoSheetOpen() {
        let intent = PendingTransactionIntent()
        intent.shouldPresentAdd = true

        #expect(intent.consume(isEditSheetOpen: false) == true)
        #expect(intent.shouldPresentAdd == false)
        // Second consume: nothing pending.
        #expect(intent.consume(isEditSheetOpen: false) == false)
    }

    @Test func doesNotConsumeWhileEditSheetOpen() {
        let intent = PendingTransactionIntent()
        intent.shouldPresentAdd = true

        #expect(intent.consume(isEditSheetOpen: true) == false)
        // Flag preserved so it can present once the edit sheet closes.
        #expect(intent.shouldPresentAdd == true)
        #expect(intent.consume(isEditSheetOpen: false) == true)
    }

    @Test func consumeIsFalseWhenNothingPending() {
        let intent = PendingTransactionIntent()
        #expect(intent.consume(isEditSheetOpen: false) == false)
    }
}
