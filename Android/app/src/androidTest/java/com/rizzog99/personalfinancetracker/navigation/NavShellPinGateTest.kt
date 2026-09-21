package com.rizzog99.personalfinancetracker.navigation

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.data.security.PinLock
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * Parity `M1-NAV-SHELL` (#110) `AC-01`: the startup gates must not take the shell away once a normal
 * startup has completed.
 *
 * `PersonalFinanceTrackerApp` chooses between the unlock screen and [PersonalFinanceNavHost] on
 * `pinLockRepository.state`, which is a flow, not a launch-time snapshot. Setting a PIN from
 * Settings therefore pushes the gate back in front of a session that is already past it. #80 owns
 * PIN behavior; this test owns the navigation-shell consequence — the shell is replaced, and the
 * `NavHost` that leaves the composition takes the user's selected destination with it.
 *
 * The PIN is written through the production repository and cleared again in [clearPin], so the
 * device is left the way the rest of the suite expects to find it.
 */
@RunWith(AndroidJUnit4::class)
class NavShellPinGateTest {

    val rule = createAndroidComposeRule<MainActivity>()

    /** Ordered outside the activity rule for the same reason as [NavShellEvidenceTest.chain]. */
    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking { app.pinLockRepository.clearPin() }
        })
        .around(rule)

    private val m = NavShellMarkers()

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as PersonalFinanceApplication

    @Before
    fun shellIsShowing() {
        rule.waitForIdle()
        assertEquals(PinLock.NotSet, app.pinLockRepository.state.value)
    }

    /** This test sets a PIN on purpose; leave the device the way the rest of the suite expects it. */
    @After
    fun clearPin() {
        runBlocking { app.pinLockRepository.clearPin() }
    }

    @Test
    fun ac01_settingAPinMidSessionKeepsTheShellAndTheSelectedDestination(): Unit = with(m) {
        rule.selectTab(insightsTab)
        rule.assertOnly(insightsTab)

        runBlocking { app.pinLockRepository.setPin(hash = "0".repeat(64), salt = "1".repeat(32)) }
        rule.waitForIdle()

        rule.assertOnly(insightsTab)
        rule.assertSingleShell()
    }
}
