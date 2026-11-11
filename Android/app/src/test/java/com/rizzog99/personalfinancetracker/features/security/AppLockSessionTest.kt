package com.rizzog99.personalfinancetracker.features.security

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * #319 `AC-01`/`AC-03`/`AC-04`: the grace state machine, ported case for case from frozen iOS
 * `BiometricGraceTests` (`b649dfff`), driven by an injected clock.
 */
class AppLockSessionTest {
    private var now = 1_000_000L

    private fun unlockedSession() = AppLockSession(clock = { now }).apply { unlock() }

    private fun away(millis: Long) {
        now += millis
    }

    @Test
    fun ac01_aShortAbsenceDoesNotRelock() {
        val session = unlockedSession()
        session.noteLeft()
        away(29_999)
        session.relockIfGraceExpired()

        assertEquals(LockState.UNLOCKED, session.state.value)
    }

    @Test
    fun ac01_aLongAbsenceRelocks() {
        val session = unlockedSession()
        session.noteLeft()
        away(31_000)
        session.relockIfGraceExpired()

        assertEquals(LockState.RELOCKED, session.state.value)
    }

    /** The boundary belongs to the lock: at exactly the interval, ask again. */
    @Test
    fun ac01_theBoundaryRelocks() {
        val session = unlockedSession()
        session.noteLeft()
        away(30_000)
        session.relockIfGraceExpired()

        assertEquals(LockState.RELOCKED, session.state.value)
    }

    @Test
    fun ac01_leavingAloneLeavesTheSessionUnlocked() {
        val session = unlockedSession()
        session.noteLeft()

        assertEquals(LockState.UNLOCKED, session.state.value)
    }

    /** A second return without another absence must not reuse a stale timestamp. */
    @Test
    fun ac01_theTimestampIsSpentOnce() {
        val session = unlockedSession()
        session.noteLeft()
        away(1_000)
        session.relockIfGraceExpired()
        away(600_000)
        session.relockIfGraceExpired()

        assertEquals(LockState.UNLOCKED, session.state.value)
    }

    @Test
    fun ac03_screenOffSpendsTheGrace() {
        val session = unlockedSession()
        session.noteLeft()
        session.invalidateGrace()

        assertEquals(LockState.RELOCKED, session.state.value)

        // And returning inside the window does not undo it.
        away(2_000)
        session.relockIfGraceExpired()
        assertEquals(LockState.RELOCKED, session.state.value)
    }

    @Test
    fun ac03_screenOffInFrontRelocks() {
        val session = unlockedSession()
        session.invalidateGrace()

        assertEquals(LockState.RELOCKED, session.state.value)
    }

    /** A cold start has no grace to be lenient with, and nothing moves it off the full gate but a PIN. */
    @Test
    fun ac04_aFreshSessionIsColdAndStaysCold() {
        val session = AppLockSession(clock = { now })
        assertEquals(LockState.COLD, session.state.value)

        session.noteLeft()
        away(60_000)
        session.relockIfGraceExpired()
        assertEquals(LockState.COLD, session.state.value)

        session.invalidateGrace()
        assertEquals(LockState.COLD, session.state.value)
    }

    @Test
    fun ac01_unlockingARelockedSessionUnlocksIt() {
        val session = unlockedSession()
        session.invalidateGrace()
        session.unlock()

        assertEquals(LockState.UNLOCKED, session.state.value)
    }
}
