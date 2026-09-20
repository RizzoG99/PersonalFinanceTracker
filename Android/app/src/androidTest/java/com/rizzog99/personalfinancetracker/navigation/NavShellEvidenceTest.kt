package com.rizzog99.personalfinancetracker.navigation

import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.Lifecycle
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.data.security.PinLock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Parity `M1-NAV-SHELL` (#110): what only the **production activity** can prove — the startup gates
 * in `PersonalFinanceTrackerApp` are in the loop, the screens run against the real repositories, and
 * Back is a real dispatch rather than a call to `popBackStack()`.
 *
 * Back-queue identity lives in [NavShellGraphTest] instead, which drives the same production
 * `PersonalFinanceNavHost` through its `navController` seam. Neither suite builds a graph of its own.
 *
 * Out of scope on purpose: loading/empty/error states (#111), full localization (#112), TalkBack and
 * touch targets (#113), visual styling (#93).
 */
@RunWith(AndroidJUnit4::class)
class NavShellEvidenceTest {

    val rule = createAndroidComposeRule<MainActivity>()

    /**
     * The PIN is cleared *outside* the activity rule, and that ordering is the point: #109's
     * `AppBootEvidenceTest` deliberately leaves a PIN on the device so its two-invocation durability
     * run has something to survive with. Whichever class the runner happens to schedule first, this
     * suite has to reach the shell — and clearing the gate after `MainActivity` has already launched
     * would mean asserting against a lock screen. "Run `pm clear` first" is not a precondition a CI
     * gate (#114) can rely on.
     */
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

    private fun typeInActivitySearch(text: String) {
        rule.onAllNodes(hasSetTextAction()).assertCountEquals(1)
        rule.onNode(hasSetTextAction()).performTextInput(text)
        rule.waitForIdle()
    }

    // --- AC-01 initial destination -------------------------------------------------------

    @Test
    fun ac01_freshLaunchResolvesToHomeWithASingleShell(): Unit = with(m) {
        rule.assertOnly(homeTab)
        // The PIN/Unknown/recovery gates each render *instead of* the NavHost, never alongside it:
        // a completed normal startup must leave exactly one tab item per destination.
        rule.assertSingleShell()
    }

    // --- AC-02 destination selection -----------------------------------------------------

    @Test
    fun ac02_everyDirectedTransitionShowsExactlyTheRequestedDestination(): Unit = with(m) {
        for (from in tabs) {
            for (to in tabs) {
                if (from == to) continue
                rule.selectTab(from)
                rule.assertOnly(from)
                rule.selectTab(to)
                rule.assertOnly(to)
            }
        }
    }

    // --- AC-04 system Back ---------------------------------------------------------------

    /**
     * The documented Android contract: every primary selection pops back to the start destination
     * first, so the queue is only ever `[home]` or `[home, X]` (proved in [NavShellGraphTest]). Back
     * from a peer therefore always lands on Home, and Back on Home leaves the app. Frozen iOS has no
     * Back gesture to mirror — recorded as an Android-native difference on #110.
     */
    @Test
    fun ac04_backAfterSelectionSequencesReturnsToHome(): Unit = with(m) {
        listOf(
            listOf(activityTab, insightsTab),
            listOf(insightsTab, activityTab, insightsTab),
            listOf(activityTab, homeTab, insightsTab, activityTab),
        ).forEach { sequence ->
            sequence.forEach { rule.selectTab(it) }
            Espresso.pressBack()
            rule.waitForIdle()
            rule.assertOnly(homeTab)
            rule.assertSingleShell()
        }
    }

    @Test
    fun ac04_backAtTheRootLeavesTheApp(): Unit = with(m) {
        rule.assertOnly(homeTab)
        // pressBack() throws NoActivityResumedException here: leaving the app *is* the contract.
        Espresso.pressBackUnconditionally()
        assertTrue(
            "Back on the start destination must finish the activity, not blank the shell",
            rule.activityRule.scenario.state == Lifecycle.State.DESTROYED ||
                rule.activity.isFinishing,
        )
    }

    // --- AC-05 recreation ----------------------------------------------------------------

    @Test
    fun ac05_activityRecreationRestoresDestinationAndState(): Unit = with(m) {
        rule.selectTab(activityTab)
        typeInActivitySearch("coffee")

        rule.activityRule.scenario.recreate()
        rule.waitForIdle()

        rule.assertOnly(activityTab)
        rule.onNode(hasSetTextAction()).assert(hasText("coffee"))
    }

    @Test
    fun ac05_activityRecreationRestoresANonDefaultPeer(): Unit = with(m) {
        rule.selectTab(insightsTab)
        rule.activityRule.scenario.recreate()
        rule.waitForIdle()
        rule.assertOnly(insightsTab)
        rule.assertSingleShell()
    }

    // --- AC-06 compact layout ------------------------------------------------------------

    @Test
    fun ac06_compactBottomNavigationLabelsAndSelectedSemantics(): Unit = with(m) {
        tabs.forEach { rule.onNode(tab(it)).assertIsDisplayed() }
        rule.selectTab(activityTab)
        rule.onNode(tab(activityTab)).assertIsSelected()
        rule.onNode(tab(homeTab)).assertIsNotSelected()
        rule.onNode(tab(insightsTab)).assertIsNotSelected()
    }
}
