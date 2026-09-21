package com.rizzog99.personalfinancetracker.l10n

import android.app.LocaleManager
import android.os.Build
import android.os.LocaleList
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import java.util.Locale
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * Parity `M1-L10N-BASE` (#112) `AC-04`: a locale change is an ordinary Android recreation, and the
 * shell has to come back on the other side of it speaking the new language and standing where it
 * stood.
 *
 * Two mechanisms, deliberately both:
 *
 * - `scenario.recreate()` is the recreation a locale change performs, driven deterministically and
 *   independently of API level. It is what the state-retention assertions use.
 * - `LocaleManager.applicationLocales` is the *real* production trigger on this emulator (API 33+):
 *   the platform applies the new locale and recreates the activity itself. It is what the
 *   copy-changes-language assertions use, so no test-only configuration override stands in for the
 *   thing under test.
 *
 * The device's app locale is cleared in [restoreLocale] whichever way the test exits.
 */
@RunWith(AndroidJUnit4::class)
class FoundationLocaleRecreationTest {

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking { app.pinLockRepository.clearPin() }
        })
        .around(rule)

    private val en = NavShellMarkers(Locale.ENGLISH)
    private val it = NavShellMarkers(Locale.ITALIAN)

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as PersonalFinanceApplication

    @Before
    fun shellIsShowing() {
        rule.waitForIdle()
        assertEquals(PinLock.NotSet, app.pinLockRepository.state.value)
    }

    @After
    fun restoreLocale() {
        setAppLocale(null)
        runBlocking { app.pinLockRepository.clearPin() }
    }

    private fun setAppLocale(locale: Locale?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSystemService(LocaleManager::class.java).applicationLocales =
            locale?.let { LocaleList(it) } ?: LocaleList.getEmptyLocaleList()
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        rule.waitForIdle()
    }

    // --- AC-04 the language actually changes, through the platform's own mechanism ---------

    @Test
    fun ac04_aPerAppLocaleChangeSwitchesTheShellCopyBothWays() {
        assumeTrue(
            "LocaleManager per-app locales need API 33+",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
        )
        with(en) { rule.assertOnly(homeTab) }

        setAppLocale(Locale.ITALIAN)
        rule.waitUntil(10_000) {
            runCatching { rule.onAllNodes(it.tab(it.activityTab)).fetchSemanticsNodes().size == 1 }
                .getOrDefault(false)
        }
        rule.onNode(it.tab(it.activityTab)).assert(hasText(it.activityTab))
        rule.onAllNodes(en.tab(en.activityTab)).assertCountIsZero("English tab label after EN→IT")

        setAppLocale(Locale.ENGLISH)
        rule.waitUntil(10_000) {
            runCatching { rule.onAllNodes(en.tab(en.activityTab)).fetchSemanticsNodes().size == 1 }
                .getOrDefault(false)
        }
        rule.onNode(en.tab(en.activityTab)).assert(hasText(en.activityTab))
        rule.onAllNodes(it.tab(it.activityTab)).assertCountIsZero("Italian tab label after IT→EN")
    }

    // --- AC-04 the shell survives the recreation -------------------------------------------

    @Test
    fun ac04_recreationFromANonRootDestinationKeepsTheDestinationAndItsState(): Unit = with(en) {
        rule.selectTab(activityTab)
        rule.onNode(hasSetTextAction()).performTextInput("coffee")
        rule.waitForIdle()

        rule.activityRule.scenario.recreate()
        rule.waitForIdle()

        rule.assertOnly(activityTab)
        rule.assertSingleShell()
        rule.onNode(hasSetTextAction()).assert(hasText("coffee"))
    }

    /**
     * The same recreation, with the app-lock gate armed.
     *
     * `PersonalFinanceTrackerApp` documents its gate as "a PIN gates cold starts, not every
     * foreground resume". A configuration change is not a cold start — the process is alive
     * throughout — so an unlocked session must stay unlocked across it. If it does not, the unlock
     * screen renders *instead of* `PersonalFinanceNavHost` during the restoration window, the
     * NavHost never composes, its saved back stack is dropped, and the user lands back on Home:
     * exactly the shell reset AC-04 forbids, on the path a locale change takes.
     */
    @Test
    fun ac04_recreationWithAPinSetKeepsTheUnlockedSessionAndTheDestination(): Unit = with(en) {
        rule.selectTab(insightsTab)
        rule.assertOnly(insightsTab)

        runBlocking { app.pinLockRepository.setPin(hash = "0".repeat(64), salt = "1".repeat(32)) }
        rule.waitForIdle()
        rule.assertOnly(insightsTab)

        rule.activityRule.scenario.recreate()
        rule.waitForIdle()

        assertTrue(
            "An unlocked session must survive a configuration-change recreation; the unlock " +
                "screen replacing the shell here is what drops the selected destination.",
            rule.onAllNodes(anyTab).fetchSemanticsNodes().isNotEmpty(),
        )
        rule.assertOnly(insightsTab)
        rule.assertSingleShell()
    }

    /**
     * The other half of #136, and the reason the retained flag lives in a `ViewModel` rather than
     * in `rememberSaveable`: keeping an unlocked session across a configuration change must not
     * weaken the gate. A fresh activity gets a fresh `ViewModelStore`, so the PIN is still asked
     * for — which is what a cold start would see.
     */
    @Test
    fun ac04_aFreshLaunchWithAPinSetStillShowsTheUnlockScreen(): Unit = with(en) {
        runBlocking { app.pinLockRepository.setPin(hash = "0".repeat(64), salt = "1".repeat(32)) }
        rule.waitForIdle()

        rule.activityRule.scenario.close()
        androidx.test.core.app.ActivityScenario.launch(MainActivity::class.java).use { fresh ->
            rule.waitForIdle()
            rule.onNodeWithText(
                InstrumentationRegistry.getInstrumentation().targetContext
                    .getString(com.rizzog99.personalfinancetracker.R.string.pin_unlock_title),
            ).assertExists()
            assertEquals(0, rule.onAllNodes(anyTab).fetchSemanticsNodes().size)
        }
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteractionCollection.assertCountIsZero(
    what: String,
) {
    val found = fetchSemanticsNodes().size
    assertEquals("$what: expected none, found $found", 0, found)
}
