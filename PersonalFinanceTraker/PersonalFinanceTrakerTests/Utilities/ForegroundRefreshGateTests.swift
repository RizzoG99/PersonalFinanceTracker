//
//  ForegroundRefreshGateTests.swift
//  PersonalFinanceTrakerTests
//

import Testing
@testable import PersonalFinanceTraker

struct ForegroundRefreshGateTests {
    @Test func initialActivationDoesNotDuplicateBootstrap() {
        var gate = ForegroundRefreshGate()
        let shouldRefresh = gate.consumeRefreshOnActivation()

        #expect(!shouldRefresh)
    }

    @Test func activationAfterBackgroundRequestsOneRefresh() {
        var gate = ForegroundRefreshGate()
        gate.recordBackground()
        let firstActivationShouldRefresh = gate.consumeRefreshOnActivation()
        let secondActivationShouldRefresh = gate.consumeRefreshOnActivation()

        #expect(firstActivationShouldRefresh)
        #expect(!secondActivationShouldRefresh)
    }

    @Test func repeatedBackgroundPhasesCoalesceToOneRefresh() {
        var gate = ForegroundRefreshGate()
        gate.recordBackground()
        gate.recordBackground()
        let shouldRefresh = gate.consumeRefreshOnActivation()

        #expect(shouldRefresh)
    }
}
