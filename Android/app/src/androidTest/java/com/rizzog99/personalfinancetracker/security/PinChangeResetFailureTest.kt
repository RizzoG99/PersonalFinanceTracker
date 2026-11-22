package com.rizzog99.personalfinancetracker.security

import android.database.sqlite.SQLiteException
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.features.settings.SettingsSheet
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #320 `AC-06`, failure half: a wipe that throws (its Room transaction rolled back) says so in
 * generic copy, never the exception's text (#135), and leaves Settings usable. A real mid-wipe
 * Room failure cannot be provoked on demand, so the production [SettingsSheet] gets its test seam.
 */
@RunWith(AndroidJUnit4::class)
class PinChangeResetFailureTest {

    @get:Rule
    val rule = createComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication
    private fun string(id: Int) = instrumentation.targetContext.getString(id)
    private fun shown(text: String, substring: Boolean = false) =
        rule.onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun ac06_aFailedWipeShowsGenericCopyAndSettingsStaysUsable() {
        runBlocking {
            app.pinLockRepository.state.first { it !is PinLock.Unknown }
            app.pinLockRepository.clearPin()
        }
        var attempts = 0
        rule.setContent {
            PersonalFinanceTheme {
                SettingsSheet(
                    onDismiss = {}, onOpenCategories = {}, onOpenScanCategories = {}, onOpenDataTransfer = {},
                    wipe = { attempts++; throw SQLiteException("/data/data/app/databases/finance.db: disk I/O error (code 4874)") },
                )
            }
        }
        val delete = string(R.string.delete_all_data)
        rule.onNode(hasText(delete) and hasClickAction() and !hasAnyAncestor(isDialog())).performScrollTo().performClick()
        rule.onNode(hasText(delete) and hasClickAction() and hasAnyAncestor(isDialog())).performClick()

        rule.mainClock.autoAdvance = false
        val deadline = System.currentTimeMillis() + 20_000
        while (!shown(string(R.string.delete_all_data_failed)) && System.currentTimeMillis() < deadline) {
            rule.mainClock.advanceTimeByFrame()
        }
        assertTrue("failure copy shown", shown(string(R.string.delete_all_data_failed)))
        assertTrue("no raw exception text", !shown("disk I/O", substring = true) && !shown("finance.db", substring = true))
        assertTrue("no success claim", !shown(string(R.string.delete_all_data_done)))
        rule.mainClock.autoAdvance = true
        assertEquals(1, attempts)

        // Still usable: once the snackbar (which can sit over the row) is gone, the row opens the
        // confirmation again.
        rule.waitUntil(20_000) { !shown(string(R.string.delete_all_data_failed)) }
        rule.onNode(hasText(delete) and hasClickAction() and !hasAnyAncestor(isDialog())).performScrollTo().performClick()
        rule.waitUntil(20_000) {
            rule.onAllNodes(hasText(delete) and hasAnyAncestor(isDialog())).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
