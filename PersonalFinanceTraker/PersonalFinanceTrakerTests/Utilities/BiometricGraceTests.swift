//
//  BiometricGraceTests.swift
//  PersonalFinanceTrakerTests
//

import Testing
import Foundation
@testable import PersonalFinanceTraker

/// The grace period only, driven by injected dates — no LocalAuthentication involved.
///
/// `@MainActor` because the service publishes: Swift Testing runs cases on arbitrary threads,
/// and mutating `@Published` off the main thread trips SwiftUI's runtime check in Xcode even
/// though the command-line runner lets it through.
@MainActor
struct BiometricGraceTests {
    private func unlockedService(grace: TimeInterval = 30) -> BiometricAuthService {
        let service = BiometricAuthService()
        service.graceInterval = grace
        service.unlock()
        return service
    }

    private let away = Date(timeIntervalSince1970: 1_000_000)

    @Test func aShortAbsenceDoesNotRelock() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)
        service.relockIfGraceExpired(now: away.addingTimeInterval(5))

        #expect(service.lockState == .unlocked)
    }

    @Test func aLongAbsenceRelocks() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)
        service.relockIfGraceExpired(now: away.addingTimeInterval(31))

        #expect(service.lockState == .locked)
    }

    // The boundary belongs to the lock: at exactly the interval, ask again.
    @Test func theBoundaryRelocks() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)
        service.relockIfGraceExpired(now: away.addingTimeInterval(30))

        #expect(service.lockState == .locked)
    }

    // Backgrounding does not lock by itself — that is what makes the grace possible, and
    // it is safe only because the privacy cover follows the scene phase instead.
    @Test func backgroundingAloneLeavesTheAppUnlocked() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)

        #expect(service.lockState == .unlocked)
    }

    // A second foreground without another absence must not consume a stale timestamp and
    // relock an app that never left.
    @Test func theTimestampIsSpentOnce() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)
        service.relockIfGraceExpired(now: away.addingTimeInterval(1))
        service.relockIfGraceExpired(now: away.addingTimeInterval(600))

        #expect(service.lockState == .unlocked)
    }

    // The device screen locked while the app was away: the grace assumed the phone was
    // still in its owner's hands.
    @Test func aDeviceLockSpendsTheGrace() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)
        service.invalidateGrace()

        #expect(service.lockState == .locked)

        // And returning inside the window does not undo it.
        service.relockIfGraceExpired(now: away.addingTimeInterval(2))
        #expect(service.lockState == .locked)
    }

    // A cold launch starts locked with no timestamp — nothing to be lenient about.
    @Test func aFreshServiceIsLockedAndHasNoGrace() {
        let service = BiometricAuthService()
        #expect(service.lockState == .locked)

        service.relockIfGraceExpired(now: away)
        #expect(service.lockState == .locked)
    }

    // Face ID's HUD deactivates our scene; a real backgrounding must clear that
    // suppression, or the cover would stay off for a genuine app switch.
    @Test func backgroundingClearsTheSystemPromptSuppression() {
        let service = unlockedService()
        service.noteBackgrounded(now: away)

        #expect(service.isSystemAuthInFlight == false)
    }
}
