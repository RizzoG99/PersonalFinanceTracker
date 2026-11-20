package com.rizzog99.personalfinancetracker.security

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #320 (`DRIFT-2026-10-DESTRUCTIVE`): Change PIN and Delete all data ask for the current PIN first,
 * as frozen iOS `PINSetupViewModel` (`.verifyCurrentPin`) and `PINConfirmationView` do at `b649dfff`.
 * Drives the production [MainActivity] from an unlocked session.
 */
@RunWith(AndroidJUnit4::class)
class PinChangeResetTest {

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.databaseProbed.first { it }
                app.pinLockRepository.state.first { it !is PinLock.Unknown }
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                app.preferencesRepository.setBiometricEnabled(false)
                app.pinLockRepository.setPin(hash = PinCodec.hash(PIN, SALT), salt = SALT)
            }
        })
        .around(rule)

    private val m = NavShellMarkers()
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app: PersonalFinanceApplication
        get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication

    private fun string(id: Int) = instrumentation.targetContext.getString(id)
    private fun shown(text: String) = rule.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty()
    private fun awaitShown(text: String) = rule.waitUntil(DEADLINE) { shown(text) }

    private fun type(pin: String) {
        pin.forEach { digit ->
            rule.onNode(hasText(digit.toString()) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                .performClick()
        }
        rule.waitForIdle()
    }

    private fun storedMatches(pin: String): Boolean {
        val secret = (app.pinLockRepository.state.value as PinLock.Set).secret
        return PinCodec.matches(pin, secret.salt, secret.hash)
    }

    private fun transactionCount(): Int =
        app.database.query("SELECT COUNT(*) FROM transactions", null).use { it.moveToFirst(); it.getInt(0) }

    private fun insertTransaction() {
        app.database.openHelper.writableDatabase.execSQL(
            "INSERT INTO transactions VALUES ('tx-320',0,'-12.99','Netflix','Bills',NULL,'EUR',NULL,NULL)",
        )
    }

    private fun pressBack() {
        rule.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
    }

    @Before
    fun unlockAndOpenSettings() {
        assertTrue("precondition: PIN set", app.pinLockRepository.state.value is PinLock.Set)
        awaitShown(string(R.string.pin_unlock_title))
        type(PIN)
        rule.waitUntil(DEADLINE) { rule.onAllNodes(m.anyTab).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(hasContentDescription(string(R.string.settings_title)) and hasClickAction()).performClick()
        awaitShown(string(R.string.security_section))
    }

    @After
    fun clearPin() {
        runBlocking { app.pinLockRepository.clearPin() }
    }

    private fun openChangePin() {
        rule.onNode(hasText(string(R.string.change_pin)) and hasClickAction()).performScrollTo().performClick()
        rule.waitForIdle()
    }

    private fun confirmDeleteAll() {
        rule.onNode(hasText(string(R.string.delete_all_data)) and hasClickAction() and !hasAnyAncestor(isDialog()))
            .performScrollTo().performClick()
        rule.onNode(hasText(string(R.string.delete_all_data)) and hasClickAction() and hasAnyAncestor(isDialog()))
            .performClick()
        rule.waitForIdle()
    }

    @Test
    fun ac01_changePinAsksForTheCurrentPinFirst() {
        openChangePin()
        awaitShown(string(R.string.pin_current_title))
        assertFalse(shown(string(R.string.pin_create_title)))

        type(WRONG)
        awaitShown(string(R.string.pin_incorrect))
        assertTrue("still on the current-PIN step", shown(string(R.string.pin_current_title)))

        type(PIN)
        awaitShown(string(R.string.pin_new_title))
        assertTrue("stored PIN unchanged", storedMatches(PIN))
    }

    @Test
    fun ac02_newPinMustDifferAndReplacesTheOldOne() {
        openChangePin()
        awaitShown(string(R.string.pin_current_title))
        type(PIN)
        awaitShown(string(R.string.pin_new_title))

        type(PIN)
        awaitShown(string(R.string.pin_must_differ))
        assertTrue("still on the new-PIN step", shown(string(R.string.pin_new_title)))

        type(NEW_PIN)
        awaitShown(string(R.string.pin_new_confirm_title))
        type(NEW_PIN)
        awaitShown(string(R.string.security_section))
        rule.waitUntil(DEADLINE) { storedMatches(NEW_PIN) }
        assertFalse("the old PIN no longer matches", storedMatches(PIN))
    }

    @Test
    fun ac01_backDuringChangePinReturnsToSettingsWithThePinUnchanged() {
        openChangePin()
        awaitShown(string(R.string.pin_current_title))
        pressBack()
        awaitShown(string(R.string.security_section))
        assertTrue(storedMatches(PIN))
    }

    @Test
    fun ac03_deleteAsksForThePin_closeBackAndWrongPinKeepData_rightPinErases() {
        insertTransaction()
        assertEquals("precondition", 1, transactionCount())

        confirmDeleteAll()
        awaitShown(string(R.string.delete_all_data_pin_subtitle))
        assertTrue(shown(string(R.string.pin_unlock_title)))
        // The semantics action, as TalkBack would: a raw touch here was refused by the AVD once.
        rule.onNode(hasContentDescription(string(R.string.dismiss)) and hasClickAction())
            .performSemanticsAction(SemanticsActions.OnClick)
        awaitShown(string(R.string.security_section))
        assertEquals("closing erases nothing", 1, transactionCount())

        confirmDeleteAll()
        awaitShown(string(R.string.delete_all_data_pin_subtitle))
        pressBack()
        awaitShown(string(R.string.security_section))
        assertEquals("Back erases nothing", 1, transactionCount())

        confirmDeleteAll()
        awaitShown(string(R.string.delete_all_data_pin_subtitle))
        type(WRONG)
        awaitShown(string(R.string.pin_incorrect))
        assertEquals("a wrong PIN erases nothing", 1, transactionCount())

        type(PIN)
        rule.waitUntil(DEADLINE) { transactionCount() == 0 }
        awaitShown(string(R.string.security_section))
    }

    @Test
    fun ac04_withoutAPinDeleteErasesWithNoGate() {
        runBlocking { app.pinLockRepository.clearPin() }
        rule.waitForIdle()
        insertTransaction()
        assertEquals("precondition", 1, transactionCount())

        confirmDeleteAll()
        rule.waitUntil(DEADLINE) { transactionCount() == 0 }
        assertFalse(shown(string(R.string.delete_all_data_pin_subtitle)))
    }

    @Test
    fun ac06_aSuccessfulWipeSaysSo() {
        runBlocking { app.pinLockRepository.clearPin() }
        rule.waitForIdle()
        confirmDeleteAll()
        // A 4 s snackbar can come and go inside one idle sync while the clock auto-advances.
        rule.mainClock.autoAdvance = false
        val deadline = System.currentTimeMillis() + DEADLINE
        while (!shown(string(R.string.delete_all_data_done)) && System.currentTimeMillis() < deadline) {
            rule.mainClock.advanceTimeByFrame()
        }
        assertTrue(shown(string(R.string.delete_all_data_done)))
        rule.mainClock.autoAdvance = true
    }

    private companion object {
        const val PIN = "135790"
        const val NEW_PIN = "246802"
        const val WRONG = "000000"
        const val SALT = "00112233445566778899aabbccddeeff"
        const val DEADLINE = 20_000L
    }
}
