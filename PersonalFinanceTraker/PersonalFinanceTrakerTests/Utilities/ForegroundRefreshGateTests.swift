//
//  ForegroundRefreshGateTests.swift
//  PersonalFinanceTrakerTests
//

import Testing
@testable import PersonalFinanceTraker

struct ForegroundRefreshGateTests {
    @Test func initialActivationDoesNotDuplicateBootstrap() {
        var gate = ForegroundRefreshGate()
        let shouldRefresh = gate.consumeRefreshOnActivation(revision: 0)

        #expect(!shouldRefresh)
    }

    @Test func activationAfterBackgroundRequestsOneRefresh() {
        var gate = ForegroundRefreshGate()
        _ = gate.consumeRefreshOnActivation(revision: 0)
        gate.recordBackground()
        let firstActivationShouldRefresh = gate.consumeRefreshOnActivation(revision: 0)
        let secondActivationShouldRefresh = gate.consumeRefreshOnActivation(revision: 0)

        #expect(firstActivationShouldRefresh)
        #expect(!secondActivationShouldRefresh)
    }

    @Test func repeatedBackgroundPhasesCoalesceToOneRefresh() {
        var gate = ForegroundRefreshGate()
        _ = gate.consumeRefreshOnActivation(revision: 0)
        gate.recordBackground()
        gate.recordBackground()
        let shouldRefresh = gate.consumeRefreshOnActivation(revision: 0)

        #expect(shouldRefresh)
    }

    /// Siri quick-add while the app is only `.inactive`: no background, but the store moved.
    @Test func inactiveBlipWithAWriteRequestsRefresh() {
        var gate = ForegroundRefreshGate()
        _ = gate.consumeRefreshOnActivation(revision: 3)
        let afterWrite = gate.consumeRefreshOnActivation(revision: 4)
        let afterIdleBlip = gate.consumeRefreshOnActivation(revision: 4)

        #expect(afterWrite)
        #expect(!afterIdleBlip)
    }
}
