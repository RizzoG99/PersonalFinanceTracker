import Foundation
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

    @Test func consumesPendingHabitTemplateOnce() {
        let intent = PendingTransactionIntent()
        intent.shouldReviewHabitTemplate = true

        #expect(intent.consumeHabitTemplate(isSheetOpen: false))
        #expect(!intent.shouldReviewHabitTemplate)
        #expect(!intent.consumeHabitTemplate(isSheetOpen: false))
    }

    @Test func preservesWidgetReviewWhileTransactionSheetIsOpen() {
        let intent = PendingTransactionIntent()
        intent.shouldReviewHabitTemplate = true

        #expect(!intent.consumeHabitTemplate(isSheetOpen: true))
        #expect(intent.shouldReviewHabitTemplate)
    }

    @Test func decodesRepeatTemplateFromWidgetURL() {
        let url = URL(string: "personalfinancetraker://review-transaction?amount=5.5&isExpense=true&category=Food&note=Lunch")!
        let request = PendingHabitTemplateRequest(widgetURL: url)

        #expect(request?.amount == 5.5)
        #expect(request?.isExpense == true)
        #expect(request?.category == "Food")
        #expect(request?.note == "Lunch")
    }

    @Test func mapsWidgetTemplateToAnUnsavedTransactionDraft() {
        let request = PendingHabitTemplateRequest(
            amount: 5.5,
            isExpense: true,
            category: "Food",
            note: "Lunch",
            createdAt: .now
        )

        let draft = request.transactionDraft
        #expect(draft.amount == 5.5)
        #expect(draft.transactionType == .expense)
        #expect(draft.categoryName == "Food")
        #expect(draft.note == "Lunch")
    }
}
