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

        assertEquals(LockState.UNLOCKED, session.state)
    }

    @Test
    fun ac01_aLongAbsenceRelocks() {
        val session = unlockedSession()
        session.noteLeft()
        away(31_000)
        session.relockIfGraceExpired()

        assertEquals(LockState.RELOCKED, session.state)
    }

    /** The boundary belongs to the lock: at exactly the interval, ask again. */
    @Test
    fun ac01_theBoundaryRelocks() {
        val session = unlockedSession()
        session.noteLeft()
        away(30_000)
        session.relockIfGraceExpired()

        assertEquals(LockState.RELOCKED, session.state)
    }

    @Test
    fun ac01_leavingAloneLeavesTheSessionUnlocked() {
        val session = unlockedSession()
        session.noteLeft()

        assertEquals(LockState.UNLOCKED, session.state)
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

        assertEquals(LockState.UNLOCKED, session.state)
    }

    /** Screen off while away: a return well inside the 30 s still asks. */
    @Test
    fun ac03_screenOffWhileAwaySpendsTheGrace() {
        val session = unlockedSession()
        session.noteLeft()
        session.invalidateGrace()
        away(2_000)
        session.relockIfGraceExpired()

        assertEquals(LockState.RELOCKED, session.state)
    }

    /**
     * Screen off in front: the activity stops right after, and the lock lands on the return — never
     * mid-frame over a focused text field.
     */
    @Test
    fun ac03_screenOffInFrontRelocksOnTheReturn() {
        val session = unlockedSession()
        session.invalidateGrace()
        session.noteLeft()
        assertEquals(LockState.UNLOCKED, session.state)

        away(1_000)
        session.relockIfGraceExpired()
        assertEquals(LockState.RELOCKED, session.state)
    }

    /** Without a PIN nothing relocks, and the spent grace does not linger into a later PIN. */
    @Test
    fun ac08_withoutAPinTheReturnClearsEverything() {
        val session = unlockedSession()
        session.noteLeft()
        session.invalidateGrace()
        away(60_000)
        session.relockIfGraceExpired(canRelock = false)
        assertEquals(LockState.UNLOCKED, session.state)
        assertEquals(false, session.away)

        session.noteLeft()
        away(1_000)
        session.relockIfGraceExpired()
        assertEquals(LockState.UNLOCKED, session.state)
    }

    @Test
    fun ac02_awayFollowsTheDeparture() {
        val session = unlockedSession()
        session.noteLeft()
        assertEquals(true, session.away)
        session.relockIfGraceExpired()
        assertEquals(false, session.away)
    }

    /** A cold start has no grace to be lenient with, and nothing moves it off the full gate but a PIN. */
    @Test
    fun ac04_aFreshSessionIsColdAndStaysCold() {
        val session = AppLockSession(clock = { now })
        assertEquals(LockState.COLD, session.state)

        session.noteLeft()
        away(60_000)
        session.relockIfGraceExpired()
        assertEquals(LockState.COLD, session.state)

        session.invalidateGrace()
        assertEquals(LockState.COLD, session.state)
    }

    @Test
    fun ac01_unlockingARelockedSessionUnlocksIt() {
        val session = unlockedSession()
        session.invalidateGrace()
        session.relockIfGraceExpired()
        assertEquals(LockState.RELOCKED, session.state)
        session.unlock()

        assertEquals(LockState.UNLOCKED, session.state)
    }
}
