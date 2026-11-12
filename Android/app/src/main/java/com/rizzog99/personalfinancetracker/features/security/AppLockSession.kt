package com.rizzog99.personalfinancetracker.features.security

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.rizzog99.personalfinancetracker.ui.components.TextFocusReleasers

/** Where this activity is in the app-lock cycle (#319). */
enum class LockState {
    /** Never past the gate since the activity was created: the full-screen PIN gate, no shell yet. */
    COLD,
    UNLOCKED,

    /** Was unlocked, then the grace ran out or the screen turned off: the shell stays, covered. */
    RELOCKED,
}

/**
 * The app-lock session, held where a configuration change cannot reach it.
 *
 * A `remember`ed flag here was #136: the composition dies with the activity, so a locale change —
 * or a rotation, or a dark-mode switch — reset it and put the PIN in front of a session already past
 * the gate.
 *
 * ponytail: a `ViewModel`, not `rememberSaveable` and not app scope. `rememberSaveable` survives a
 * **process kill**, so a cold start would come back unlocked. App scope would leak an unlocked
 * session between instrumented test classes, which share one process. A `ViewModel` survives
 * configuration changes and dies with the activity — so a cold start is always [LockState.COLD].
 *
 * The grace mirrors frozen iOS `BiometricAuthService` (`b649dfff`): leaving notes the time, and the
 * return decides. Away for [GRACE_MILLIS] or more relocks; the boundary belongs to the lock.
 *
 * Snapshot state, not `StateFlow`: a flow read through `collectAsState` lags a frame, and in that
 * frame the transaction form saw "focus saved, app not away" and gave focus straight back to a field
 * that was leaving — the window race behind the Compose 1.6 crash in `ReleaseTextFocusWhileObscured`.
 */
internal class AppLockSession(
    /** Monotonic, so a wall-clock change cannot skip the lock (#319 D-05). Swapped by tests. */
    var clock: () -> Long = SystemClock::elapsedRealtime,
) : ViewModel() {
    var state by mutableStateOf(LockState.COLD)
        private set

    /** Another activity is on top (Overview, another app): hide the shell from the live tile. */
    var privacyCover by mutableStateOf(false)

    /** The activity is stopped. */
    var away by mutableStateOf(false)
        private set

    /** Released synchronously by the activity as it leaves or as Overview takes over. */
    val textFocus = TextFocusReleasers()

    /** In memory only: an absence is spent by the first return that looks at it. */
    private var leftAt: Long? = null
    private var graceSpent = false

    fun unlock() {
        state = LockState.UNLOCKED
    }

    /** The app left the foreground. Does not lock: the return decides, by how long it lasted. */
    fun noteLeft() {
        leftAt = clock()
        away = true
    }

    /**
     * The app is back in front. Relocks when [canRelock] (a PIN is set) and the absence used up the
     * grace — by lasting [GRACE_MILLIS] or more, or by a screen-off in between.
     */
    fun relockIfGraceExpired(canRelock: Boolean = true) {
        val left = leftAt
        val spent = graceSpent
        leftAt = null
        graceSpent = false
        if (canRelock && state == LockState.UNLOCKED &&
            (spent || (left != null && clock() - left >= GRACE_MILLIS))
        ) {
            // Text focus goes first, here rather than on leaving: the lock window must not land on a
            // focused field, and by now the system has already hidden the keyboard. Releasing it in
            // onStop raced a keyboard still animating in and crashed Compose 1.6's text input.
            textFocus.releaseAll()
            state = LockState.RELOCKED
        }
        // After the lock decision, so nothing ever observes "back, and not locked" in between.
        away = false
    }

    /**
     * The screen turned off: the grace assumed the phone stayed with its owner, and that is the
     * moment it stops being safe to assume. Spent at once, however short the absence.
     *
     * ponytail: spent, not locked on the spot. The lock appears on the return, which a screen-off
     * guarantees (the activity stops) — so it never lands on top of a still-focused text field.
     * With the screen off, nobody can tell the difference.
     */
    fun invalidateGrace() {
        graceSpent = true
    }

    companion object {
        const val GRACE_MILLIS = 30_000L
    }
}
