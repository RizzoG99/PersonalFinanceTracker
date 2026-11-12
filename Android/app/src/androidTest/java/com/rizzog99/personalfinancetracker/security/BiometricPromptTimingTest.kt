package com.rizzog99.personalfinancetracker.security

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.features.security.PinUnlockScreen
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #319 `AC-06`: the biometric prompt is started only for an app in front of an unlocked device,
 * once per return — frozen iOS asks only at the end of a real return from the background
 * (`AuthenticationWrapper.swift:282-339` at `b649dfff`).
 *
 * A relock caused by the screen turning off composes the PIN screen while the activity is stopped;
 * starting `BiometricPrompt` then would put it behind the lock screen (or fail the fragment commit).
 */
@RunWith(AndroidJUnit4::class)
class BiometricPromptTimingTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var requests = 0
    private var unlocked = 0
    private var showLock by mutableStateOf(false)

    private fun host(request: (() -> Unit) -> Unit = { requests++ }) {
        val salt = "timing-salt"
        val hash = PinCodec.hash("123456", salt)
        rule.setContent {
            PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                if (showLock) {
                    PinUnlockScreen(
                        expectedHash = hash,
                        expectedSalt = salt,
                        biometricEnabled = true,
                        onUnlocked = { unlocked++ },
                        requestBiometric = request,
                    )
                }
            }
        }
        rule.waitForIdle()
    }

    private fun moveTo(state: Lifecycle.State) {
        rule.activityRule.scenario.moveToState(state)
        rule.waitForIdle()
    }

    @Test
    fun ac06_aLockComposedWhileStoppedWaitsForTheReturn() {
        host()
        moveTo(Lifecycle.State.CREATED)

        showLock = true
        rule.waitForIdle()
        assertEquals("no prompt while the app is not in front", 0, requests)

        moveTo(Lifecycle.State.RESUMED)
        assertEquals("one prompt once the app is back in front", 1, requests)
    }

    @Test
    fun ac06_oncePerReturnFromTheBackground() {
        host()
        showLock = true
        rule.waitForIdle()
        assertEquals("precondition: one prompt when the lock appears in front", 1, requests)

        // Losing focus without leaving (a system dialog, the notification shade) is not a return.
        moveTo(Lifecycle.State.STARTED)
        moveTo(Lifecycle.State.RESUMED)
        assertEquals(1, requests)

        // Leaving and coming back is.
        moveTo(Lifecycle.State.CREATED)
        moveTo(Lifecycle.State.RESUMED)
        assertEquals(2, requests)
    }

    /** A success that arrives after its attempt ended (stopped, or superseded) must not unlock. */
    @Test
    fun ac06_aStaleSuccessDoesNotUnlock() {
        val callbacks = mutableListOf<() -> Unit>()
        host(request = { onSuccess -> callbacks += onSuccess })
        showLock = true
        rule.waitForIdle()
        assertEquals("precondition: one attempt", 1, callbacks.size)

        moveTo(Lifecycle.State.CREATED)
        rule.runOnIdle { callbacks[0]() }
        assertEquals("success after stop", 0, unlocked)

        moveTo(Lifecycle.State.RESUMED)
        assertEquals("precondition: a new attempt on return", 2, callbacks.size)
        rule.runOnIdle { callbacks[0]() }
        assertEquals("the superseded attempt's success", 0, unlocked)

        rule.runOnIdle { callbacks[1]() }
        assertEquals("the current attempt's success unlocks", 1, unlocked)
    }

    /** A prompt that cannot start must leave the PIN pad working, not take the process down (#133). */
    @Test
    fun ac06_aPromptThatFailsToStartLeavesThePinWorking() {
        host(request = { requests++; error("no biometric hardware") })
        showLock = true
        rule.waitForIdle()
        assertEquals("precondition: the failing prompt was attempted", 1, requests)

        "123456".forEach { digit ->
            rule.onNode(
                hasText(digit.toString()) and
                    SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button),
            ).performClick()
        }
        rule.waitUntil(20_000) { unlocked == 1 }
    }
}
