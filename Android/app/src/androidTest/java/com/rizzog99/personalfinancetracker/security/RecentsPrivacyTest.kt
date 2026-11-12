package com.rizzog99.personalfinancetracker.security

import android.graphics.Bitmap
import android.os.Build
import android.view.WindowManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.matcher.RootMatchers.isDialog
import androidx.test.espresso.matcher.ViewMatchers.isRoot
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.ui.test.hasTestTag
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.security.AppLockSession
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #319 `AC-05`: the Recents screen never shows finance content, PIN or not — frozen iOS covers the
 * task-switcher snapshot whenever the scene is not active (`LockOverlayDecision.swift:54-71`).
 *
 * D-02 (owner): Android 13+ hides only the Recents thumbnail, so screenshots keep working; Android
 * 8–12 have no such switch, so `FLAG_SECURE` hides it there (and blocks screenshots too). The flag
 * assertions run on whichever API the device has; CI covers 26 and 34, the local AVD 36.
 *
 * The Recents captures are evidence for the visual review (no balance or draft on the tile), not
 * assertions: the tile is drawn by the launcher, outside anything a semantics query can reach.
 */
@RunWith(AndroidJUnit4::class)
class RecentsPrivacyTest {

    val rule = createAndroidComposeRule<MainActivity>()

    /** No PIN at launch and one recognisable income on Home. */
    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.databaseProbed.first { it }
                app.pinLockRepository.state.first { it !is PinLock.Unknown }
                app.pinLockRepository.clearPin()
                app.preferencesRepository.setBiometricEnabled(false)
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                val salary = app.categoryRepository.observeAll().first().first { it.type == TransactionType.INCOME }
                app.transactionRepository.upsert(
                    FinanceTransaction(
                        id = "recents-income",
                        timestamp = Instant.now(),
                        amount = BigDecimal("1234.56"),
                        note = "Recents fixture",
                        categoryLabel = salary.name,
                        categoryId = salary.id,
                        currencyCode = "EUR",
                        goalId = null,
                        recurrenceRuleId = null,
                    ),
                )
            }
        })
        .around(rule)

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app: PersonalFinanceApplication
        get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication
    private val secureExpected = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU

    private fun string(id: Int) = instrumentation.targetContext.getString(id)

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).use { pfd ->
            java.io.FileInputStream(pfd.fileDescriptor).use { it.readBytes() }
        }
    }

    @After
    fun clearPin() = runBlocking { app.pinLockRepository.clearPin() }

    private fun awaitHome() {
        rule.waitUntil(DEADLINE) {
            rule.onAllNodes(hasText(string(R.string.home_title))).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun activityWindowIsSecure(): Boolean {
        var flags = 0
        rule.activityRule.scenario.onActivity { flags = it.window.attributes.flags }
        return flags and WindowManager.LayoutParams.FLAG_SECURE != 0
    }

    private val coverShown
        get() = rule.onAllNodes(hasTestTag(PRIVACY_COVER_TAG)).fetchSemanticsNodes().isNotEmpty()

    /**
     * Opens Overview, photographs the screen, and comes back. Overview keeps the app *resumed* as a
     * live tile, so the wait is for the launcher to hold the active window, not for a lifecycle state.
     */
    private fun captureRecents(state: String, expectCover: Boolean) {
        val pkg = instrumentation.targetContext.packageName
        assertTrue("precondition: the app is in front", !coverShown)
        shell("input keyevent KEYCODE_APP_SWITCH")
        rule.waitUntil(DEADLINE) {
            instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString().let { it != null && it != pkg }
        }
        if (expectCover) rule.waitUntil(DEADLINE) { coverShown }
        if (Build.VERSION.SDK_INT < 29 || secureExpected) {
            // No live tile before API 29; and a FLAG_SECURE screen photographs black by design.
            rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
            return
        }
        instrumentation.uiAutomation.waitForIdle(500, 5_000)
        val shot = instrumentation.uiAutomation.takeScreenshot()
        val name = "recents-$state-api${Build.VERSION.SDK_INT}-${Build.MODEL.replace(' ', '_')}.png"
        File(CaptureHarness.outputDir("relock-319"), name).outputStream().use {
            shot.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        // Back to the same activity in the same task: NEW_TASK finds the task, REORDER_TO_FRONT the
        // instance. A launcher intent or the scenario did not bring it back on the tablet AVD.
        shell("am start -W -f 0x10020000 -n $pkg/.MainActivity")
        rule.waitUntil(DEADLINE) { !coverShown }
    }

    @Test
    fun ac05_withoutAPinRecentsHidesHome() {
        awaitHome()
        assertEquals(
            "FLAG_SECURE on API ${Build.VERSION.SDK_INT}: required below 33, absent from 33 (D-02)",
            secureExpected,
            activityWindowIsSecure(),
        )
        captureRecents("home-nopin", expectCover = Build.VERSION.SDK_INT >= 29)
    }

    /** The sheet draws its own cover too, so an open sheet and its draft are hidden as well. */
    @Test
    fun ac05_anOpenSheetIsHiddenToo() {
        awaitHome()
        rule.onNode(hasContentDescription(string(R.string.add_transaction)) and hasClickAction()).performClick()
        rule.waitUntil(DEADLINE) { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().size == 2 }
        // The amount field, as SaveFeedbackTest types it: the dependable input in this sheet.
        rule.onAllNodes(hasSetTextAction())[0].performTextInput("12.50")
        instrumentation.uiAutomation.waitForIdle(1_000, 10_000) // #398: let the keyboard settle.
        val before = amountText()
        assertTrue("precondition: an amount in the open sheet; got '$before'", before.isNotBlank())

        captureRecents("sheet-nopin", expectCover = Build.VERSION.SDK_INT >= 29)
        assertEquals("the sheet and its draft survive Overview", before, amountText())
    }

    private fun amountText(): String =
        rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().firstOrNull()
            ?.config?.getOrNull(SemanticsProperties.EditableText)?.text.orEmpty()

    @Test
    fun ac05_relockedOverAnOpenSheetStaysHidden() {
        awaitHome()
        var now = 1_000_000L
        rule.activityRule.scenario.onActivity {
            ViewModelProvider(it)[AppLockSession::class.java].clock = { now }
        }
        runBlocking { app.pinLockRepository.setPin(hash = PinCodec.hash("123456", "recents-salt"), salt = "recents-salt") }
        rule.onNode(hasContentDescription(string(R.string.add_transaction)) and hasClickAction()).performClick()
        rule.waitUntil(DEADLINE) { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().size == 2 }
        // No text field focused on the way out: leaving with the keyboard up is #398, a Compose 1.6
        // crash that reproduces on unchanged code. A covered draft is ac05_anOpenSheetIsHiddenToo's job.
        instrumentation.uiAutomation.waitForIdle(1_000, 10_000)

        rule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        now += 30_000
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        rule.waitUntil(DEADLINE) {
            rule.onAllNodes(hasText(string(R.string.pin_unlock_title))).fetchSemanticsNodes().isNotEmpty()
        }
        assertTrue(
            "precondition: the lock is up over the sheet",
            rule.onAllNodes(hasText(string(R.string.pin_unlock_title)) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
                .fetchSemanticsNodes().isNotEmpty() &&
                rule.onAllNodes(hasText("1") and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                    .fetchSemanticsNodes().isNotEmpty(),
        )

        assertEquals(secureExpected, activityWindowIsSecure())
        if (secureExpected) {
            // The lock is its own window, created after the flag was set: it must carry it too.
            var dialogFlags = 0
            onView(isRoot()).inRoot(isDialog()).check { view, _ ->
                dialogFlags = (view.rootView.layoutParams as WindowManager.LayoutParams).flags
            }
            assertTrue(
                "the lock window must inherit FLAG_SECURE",
                dialogFlags and WindowManager.LayoutParams.FLAG_SECURE != 0,
            )
        }
        // Relocked, the lock window is the cover; the separate one stays away.
        captureRecents("relocked-sheet", expectCover = false)
        assertTrue("no second cover over the lock", !coverShown)
    }

    private companion object {
        const val DEADLINE = 20_000L

        /** A literal, not the production constant: the test must also compile against the red baseline. */
        const val PRIVACY_COVER_TAG = "privacyCover"
    }
}
