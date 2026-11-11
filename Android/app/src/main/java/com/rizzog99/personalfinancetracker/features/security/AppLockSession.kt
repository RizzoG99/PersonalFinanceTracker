package com.rizzog99.personalfinancetracker.features.security

import android.os.SystemClock
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

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
 */
internal class AppLockSession(
    /** Monotonic, so a wall-clock change cannot skip the lock (#319 D-05). Swapped by tests. */
    var clock: () -> Long = SystemClock::elapsedRealtime,
) : ViewModel() {
    private val _state = MutableStateFlow(LockState.COLD)
    val state: StateFlow<LockState> = _state.asStateFlow()

    /** In memory only: an absence is spent by the first return that looks at it. */
    private var leftAt: Long? = null

    fun unlock() {
        _state.value = LockState.UNLOCKED
    }

    /** The app left the foreground. Does not lock: the return decides, by how long it lasted. */
    fun noteLeft() {
        leftAt = clock()
    }

    fun relockIfGraceExpired() {
        val left = leftAt ?: return
        leftAt = null
        if (_state.value == LockState.UNLOCKED && clock() - left >= GRACE_MILLIS) {
            _state.value = LockState.RELOCKED
        }
    }

    /**
     * The screen turned off: the grace assumed the phone stayed with its owner, and that is the
     * moment it stops being safe to assume. Spent at once, however short the absence.
     */
    fun invalidateGrace() {
        leftAt = null
        if (_state.value == LockState.UNLOCKED) _state.value = LockState.RELOCKED
    }

    companion object {
        const val GRACE_MILLIS = 30_000L
    }
}
