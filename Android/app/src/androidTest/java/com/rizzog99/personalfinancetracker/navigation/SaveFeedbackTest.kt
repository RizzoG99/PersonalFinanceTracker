package com.rizzog99.personalfinancetracker.navigation

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import java.util.Locale
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.hasAnySibling
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #287 (`DRIFT-2026-10-UNDO`): saving from the shell's **+** button confirms the save and offers
 * no Undo, because frozen iOS (`b649dfff`) never offers one after Add or Edit and the Android
 * action used to do nothing.
 *
 * Hosts the production [PersonalFinanceNavHost] the way [NavShellGraphTest] does (#110 seam), so
 * the PIN gate and startup gates stay out of the way: this covers the post-gate save feedback only.
 */
@RunWith(AndroidJUnit4::class)
class SaveFeedbackTest {

    @get:Rule
    val rule = createComposeRule()

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as PersonalFinanceApplication

    private fun string(id: Int): String =
        InstrumentationRegistry.getInstrumentation().targetContext.getString(id)

    private fun transactions(): List<FinanceTransaction> =
        runBlocking { app.transactionRepository.observeAll().first() }

    @Before
    fun emptyLedgerWithDefaultCategories() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        assertEquals("precondition: empty ledger", 0, transactions().size)
        assertTrue(
            "precondition: an expense category to save into",
            app.categoryRepository.observeAll().first().any { it.type == TransactionType.EXPENSE },
        )
    }

    private fun host(widthDp: Int) {
        rule.setContent {
            val configuration = Configuration(LocalContext.current.resources.configuration)
                .apply { screenWidthDp = widthDp }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                    PersonalFinanceNavHost()
                }
            }
        }
        rule.waitForIdle()
    }

    /**
     * Opens the **+** editor and enters €12.50. The FAB is the only `add_transaction` node until the
     * sheet opens, and it leaves the shell while the sheet is up, so afterwards the only one is the
     * editor's save button.
     */
    private fun openEditorWithAmount() {
        val add = hasContentDescription(string(R.string.add_transaction)) and hasClickAction()
        rule.onAllNodes(add).assertCountEquals(1)
        rule.onNode(add).performClick()
        rule.waitForIdle()
        // Amount, then the note field.
        rule.onAllNodes(hasSetTextAction()).assertCountEquals(2)
        rule.onAllNodes(hasSetTextAction())[0].performTextInput("12.50")
        rule.waitForIdle()
    }

    /**
     * Saves and returns how many Undo nodes were on screen while "Transaction saved" was. Both are
     * read in the same check, so an Undo cannot slip out between the two observations.
     */
    private fun saveAndCountUndo(): Int {
        val save = hasContentDescription(string(R.string.add_transaction)) and hasClickAction()
        rule.onAllNodes(save).assertCountEquals(1)
        // Manual clock from here: with auto-advance, an idle sync may jump the virtual clock past
        // the snackbar's whole 4 s lifetime and the message is never observed. One frame at a
        // time, it is on screen for ~250 frames.
        rule.mainClock.autoAdvance = false
        rule.onNode(save).assertIsEnabled().performClick()
        var undoCount = -1
        val deadline = System.currentTimeMillis() + 20_000
        while (undoCount < 0 && System.currentTimeMillis() < deadline) {
            rule.mainClock.advanceTimeByFrame()
            if (rule.onAllNodes(hasText(string(R.string.transaction_saved))).fetchSemanticsNodes().isNotEmpty()) {
                undoCount = rule.onAllNodes(hasText(string(R.string.undo))).fetchSemanticsNodes().size
            } else {
                Thread.sleep(16)
            }
        }
        rule.mainClock.autoAdvance = true
        assertTrue("no 'Transaction saved' seen: stored=${transactions().size}", undoCount >= 0)
        return undoCount
    }

    private fun assertOneOffSaveShowsNoUndo(widthDp: Int) {
        host(widthDp)
        openEditorWithAmount()

        assertEquals("a no-op Undo must not be offered after save", 0, saveAndCountUndo())

        val stored = transactions()
        assertEquals(1, stored.size)
        assertEquals(0, BigDecimal("-12.50").compareTo(stored.single().amount))
        assertEquals(null, stored.single().recurrenceRuleId)
    }

    @Test
    fun ac01_oneOffSaveFromPlusShowsNoUndo_compact() = assertOneOffSaveShowsNoUndo(widthDp = 411)

    @Test
    fun ac01_oneOffSaveFromPlusShowsNoUndo_wide() = assertOneOffSaveShowsNoUndo(widthDp = 900)

    @Test
    fun ac02_recurringSaveFromPlusShowsNoUndo() {
        host(widthDp = 411)
        openEditorWithAmount()
        val repeat = isToggleable() and hasAnySibling(hasText(string(R.string.repeat_transaction)))
        rule.onNode(repeat).performScrollTo().assertIsOff().performClick()
        rule.waitForIdle()
        // The frequency controls only exist while Repeat is on.
        rule.onNodeWithText(string(R.string.repeats_every)).assertExists()

        assertEquals("a no-op Undo must not be offered after save", 0, saveAndCountUndo())

        val occurrences = transactions().filter { it.recurrenceRuleId != null }
        assertTrue("the generated occurrence is stored", occurrences.isNotEmpty())
        occurrences.forEach { assertEquals(0, BigDecimal("-12.50").compareTo(it.amount)) }
        val ruleId = occurrences.first().recurrenceRuleId!!
        assertNotNull("the rule is stored", runBlocking { app.database.recurrenceRuleDao().get(ruleId) })
    }

    /**
     * Step-7 evidence: the post-save snackbar in every cell the AC cares about. It asserts only
     * that the message is there with no Undo; the PNG and semantics dump are for the visual review.
     * Pull them from `ui-save-feedback/` (see the skill's `references/parity-tests.md`).
     */
    @Test
    fun capturePostSaveSnackbar() {
        val cells = listOf(
            CaptureHarness.Cell("en-light-compact"),
            CaptureHarness.Cell("it-light-compact", locale = Locale.ITALIAN),
            CaptureHarness.Cell("en-dark-compact", theme = ThemeMode.DARK),
            CaptureHarness.Cell("en-light-wide", widthDp = 900),
            CaptureHarness.Cell("it-dark-wide", locale = Locale.ITALIAN, widthDp = 900, theme = ThemeMode.DARK),
            CaptureHarness.Cell("it-light-compact-large-text", locale = Locale.ITALIAN, fontScale = 2.0f),
        )
        val cell = mutableStateOf(cells.first())
        rule.setContent {
            val current = cell.value
            val context = CaptureHarness.localeContext(LocalContext.current, current.locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = current.widthDp
                fontScale = current.fontScale
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, current.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = current.theme) { PersonalFinanceNavHost() }
            }
        }
        val outputDir = CaptureHarness.outputDir("ui-save-feedback")
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        cells.forEach { c ->
            cell.value = c
            rule.mainClock.autoAdvance = true
            rule.waitForIdle()
            val localized = CaptureHarness.localeContext(base, c.locale)
            val add = hasContentDescription(localized.getString(R.string.add_transaction)) and hasClickAction()
            rule.onNode(add).performClick()
            rule.waitForIdle()
            rule.onAllNodes(hasSetTextAction())[0].performTextInput("12.50")
            rule.waitForIdle()
            rule.mainClock.autoAdvance = false
            // The sheet is its own window, whose ComposeView re-provides LocalContext, so the locale
            // override stops at it: its save button keeps the device-language label. The snackbar
            // under review lives in the main window and is localized.
            rule.onNode(hasContentDescription(base.getString(R.string.add_transaction)) and hasClickAction())
                .performClick()
            val saved = hasText(localized.getString(R.string.transaction_saved))
            val deadline = System.currentTimeMillis() + 20_000
            while (rule.onAllNodes(saved).fetchSemanticsNodes().isEmpty() && System.currentTimeMillis() < deadline) {
                rule.mainClock.advanceTimeByFrame()
                Thread.sleep(16)
            }
            // Let the enter animation settle so the PNG shows the resting snackbar.
            rule.mainClock.advanceTimeBy(500)
            rule.onNode(saved).assertExists()
            rule.onAllNodes(hasText(localized.getString(R.string.undo))).assertCountEquals(0)
            CaptureHarness.writePng(rule, outputDir, c.id)
            CaptureHarness.writeSemantics(rule, outputDir, c.id)
            rule.mainClock.advanceTimeBy(6_000) // past the snackbar's lifetime before the next cell
        }
        rule.mainClock.autoAdvance = true
    }

    /**
     * Regression guard: delete-Undo in Activity is real and must keep working.
     *
     * Wide only (D-04 on #287): on a compact width the shell's + button covers this Undo, a
     * pre-existing defect tracked in #368 whose test belongs there.
     */
    @Test
    fun ac03_deleteUndoInActivityStillRestores_wide() {
        val id = UUID.randomUUID().toString()
        runBlocking {
            val groceries = app.categoryRepository.observeAll().first()
                .first { it.name == "Groceries" && it.type == TransactionType.EXPENSE }
            app.transactionRepository.upsert(
                FinanceTransaction(
                    id = id,
                    timestamp = Instant.now(),
                    amount = BigDecimal("-12.50"),
                    note = "coffee",
                    categoryLabel = groceries.name,
                    categoryId = groceries.id,
                    currencyCode = "EUR",
                    goalId = null,
                    recurrenceRuleId = null,
                ),
            )
        }
        host(widthDp = 900)
        with(NavShellMarkers()) { rule.selectTab(activityTab) }

        rule.onNodeWithText("coffee").performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
        val undo = hasText(string(R.string.undo)) and hasClickAction()
        // Frozen from the tap: the Undo lasts 5 s (#376), and a wait under auto-advance could run the
        // virtual clock past it on a slow emulator. The deadline is wall-clock, for the Room write.
        rule.mainClock.autoAdvance = false
        try {
            rule.onNodeWithText(string(R.string.delete_transaction)).performClick()
            val deadline = System.currentTimeMillis() + 60_000
            fun shown() = transactions().none { it.id == id } &&
                rule.onAllNodes(hasText(string(R.string.transaction_deleted))).fetchSemanticsNodes().isNotEmpty() &&
                rule.onAllNodes(undo).fetchSemanticsNodes().isNotEmpty()
            while (!shown() && System.currentTimeMillis() < deadline) {
                rule.mainClock.advanceTimeByFrame()
                Thread.sleep(16)
            }
            assertTrue("never: deleted and Undo shown", shown())
            rule.mainClock.advanceTimeBy(500) // past the enter animation, well inside the window
            // A covered Undo would swallow the tap (#368), so prove nothing clickable sits on top of it.
            val undoBounds = rule.onNode(undo).fetchSemanticsNode().boundsInWindow
            val add = rule.onAllNodes(hasContentDescription(string(R.string.add_transaction)) and hasClickAction())
                .fetchSemanticsNodes().map { it.boundsInWindow }
            assertTrue("Undo $undoBounds is covered by + $add", add.none { it.overlaps(undoBounds) })
            rule.onNode(undo).performClick()
        } finally {
            rule.mainClock.autoAdvance = true
        }
        rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == id } }
    }
}
