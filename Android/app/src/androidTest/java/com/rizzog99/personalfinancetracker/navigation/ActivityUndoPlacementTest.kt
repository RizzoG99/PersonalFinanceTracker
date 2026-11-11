package com.rizzog99.personalfinancetracker.navigation

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #368: on a phone, Activity's snackbars (above all "Transaction deleted · Undo") must not sit under
 * the shell's floating **+**. Material lifts a snackbar above a FAB only within one Scaffold, so
 * compact Activity shows its snackbars through the shell's host.
 *
 * Hosts the production [PersonalFinanceNavHost] like [SaveFeedbackTest] (#110 seam): the PIN and
 * startup gates stay out of the way. The wide case (AC-02) is `SaveFeedbackTest.ac03_…_wide`.
 */
@RunWith(AndroidJUnit4::class)
class ActivityUndoPlacementTest {

    @get:Rule
    val rule = createComposeRule()

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as PersonalFinanceApplication

    private fun string(id: Int): String =
        InstrumentationRegistry.getInstrumentation().targetContext.getString(id)

    private fun transactions(): List<FinanceTransaction> =
        runBlocking { app.transactionRepository.observeAll().first() }

    private val plus: SemanticsMatcher
        get() = hasContentDescription(string(R.string.add_transaction)) and hasClickAction()

    private val undo: SemanticsMatcher
        get() = hasText(string(R.string.undo)) and hasClickAction()

    @Before
    fun emptyLedgerWithDefaultCategories() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        assertEquals("precondition: empty ledger", 0, transactions().size)
    }

    private fun groceries() = runBlocking {
        app.categoryRepository.observeAll().first()
            .first { it.name == "Groceries" && it.type == TransactionType.EXPENSE }
    }

    /** One −12.50 EUR "coffee" expense in Groceries; returns its id. */
    private fun seedCoffee(): String = seedExpense("coffee")

    private fun seedExpense(note: String): String {
        val id = UUID.randomUUID().toString()
        val groceries = groceries()
        runBlocking {
            app.transactionRepository.upsert(
                FinanceTransaction(
                    id = id,
                    timestamp = Instant.now(),
                    amount = BigDecimal("-12.50"),
                    note = note,
                    categoryLabel = groceries.name,
                    categoryId = groceries.id,
                    currencyCode = "EUR",
                    goalId = null,
                    recurrenceRuleId = null,
                ),
            )
        }
        assertTrue("precondition: $note stored", transactions().any { it.id == id })
        return id
    }

    private fun host(widthDp: Int) {
        rule.setContent {
            val configuration = Configuration(LocalContext.current.resources.configuration)
                .apply { screenWidthDp = widthDp }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) { PersonalFinanceNavHost() }
            }
        }
        rule.waitForIdle()
        with(NavShellMarkers()) { rule.selectTab(activityTab) }
    }

    private fun swipeCoffeeLeft() = swipeLeftOn("coffee")

    private fun swipeLeftOn(note: String) {
        rule.onNodeWithText(note).performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
    }

    private fun waitForUndo() = rule.waitUntil(timeoutMillis = 20_000) {
        rule.onAllNodes(hasText(string(R.string.transaction_deleted))).fetchSemanticsNodes().isNotEmpty() &&
            rule.onAllNodes(undo).fetchSemanticsNodes().isNotEmpty()
    }

    /**
     * Nothing clickable — the **+** is the only floating control — overlaps [target]. Compact only:
     * it first proves the **+** is there, so the check cannot pass on an absent FAB.
     */
    private fun assertPlusClearOf(target: SemanticsMatcher) {
        rule.onAllNodes(plus).assertCountEquals(1)
        val targetBounds = rule.onNode(target).fetchSemanticsNode().boundsInWindow
        val plusBounds = rule.onNode(plus).fetchSemanticsNode().boundsInWindow
        assertTrue("$targetBounds is covered by + $plusBounds", !plusBounds.overlaps(targetBounds))
    }

    @Test
    fun ac01_deleteUndoRestores_compact() {
        val id = seedCoffee()
        host(widthDp = 411)

        swipeCoffeeLeft()
        rule.onNodeWithText(string(R.string.delete_transaction)).performClick()
        rule.waitUntil(timeoutMillis = 20_000) { transactions().none { it.id == id } }
        waitForUndo()
        assertPlusClearOf(undo)

        rule.onNode(undo).performClick()
        rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == id } }
        val restored = transactions().single { it.id == id }
        assertEquals(0, BigDecimal("-12.50").compareTo(restored.amount))
        rule.waitForIdle()
        // The tap reached Undo, not the +: no editor (its title is a heading with this text).
        rule.onAllNodes(hasText(string(R.string.add_transaction)) and isHeading()).assertCountEquals(0)
    }

    @Test
    fun ac03_updatedSnackbarIsClearOfPlus_compact() {
        seedCoffee()
        host(widthDp = 411)

        rule.onNodeWithText("coffee").performScrollTo().performClick()
        rule.waitForIdle()
        val save = hasContentDescription(string(R.string.save)) and hasClickAction()
        rule.onAllNodes(save).assertCountEquals(1)
        // "Transaction updated" is a 4 s snackbar: step the clock by frame so an idle sync cannot
        // jump past its whole lifetime (references/parity-tests.md).
        rule.mainClock.autoAdvance = false
        try {
            rule.onNode(save).performClick()
            val updated = hasText(string(R.string.transaction_updated))
            // Wall-clock budget for the save's Room write; the 4 s on screen is virtual and checked
            // every frame, so a long budget cannot skip it. 20 s flaked on a loaded host.
            val deadline = System.currentTimeMillis() + 60_000
            while (rule.onAllNodes(updated).fetchSemanticsNodes().isEmpty() && System.currentTimeMillis() < deadline) {
                rule.mainClock.advanceTimeByFrame()
                Thread.sleep(16)
            }
            // A missing snackbar fails here, never as the overlap below.
            assertTrue("no 'Transaction updated' seen", rule.onAllNodes(updated).fetchSemanticsNodes().isNotEmpty())
            rule.mainClock.advanceTimeBy(500) // past the enter animation
            // The message node is only as wide as its text, so it can end left of the + while the
            // snackbar's container (no semantics of its own) still runs under it: on the red run the
            // text was clear horizontally. The snackbar spans the width, so it is clear of the + only
            // when its row is entirely above the +.
            rule.onAllNodes(plus).assertCountEquals(1)
            val text = rule.onNode(updated).fetchSemanticsNode().boundsInWindow
            val plusBounds = rule.onNode(plus).fetchSemanticsNode().boundsInWindow
            assertTrue("snackbar text $text is not above + $plusBounds", text.bottom <= plusBounds.top)
        } finally {
            rule.mainClock.autoAdvance = true
        }
    }

    @Test
    fun ac03_recurringDeleteThisOnlyUndoRestores_compact() {
        val groceries = groceries()
        runBlocking {
            app.recurrenceRepository.createAndMaterialize(
                NewRecurrenceRule(
                    frequency = RecurrenceFrequency.MONTHLY,
                    interval = 1,
                    startDate = Instant.now(),
                    amount = BigDecimal("-12.50"),
                    note = "coffee",
                    categoryLabel = groceries.name,
                    categoryId = groceries.id,
                    currencyCode = "EUR",
                ),
            )
        }
        val occurrence = transactions().single { it.recurrenceRuleId != null }
        host(widthDp = 411)

        swipeCoffeeLeft()
        rule.onNodeWithText(string(R.string.delete_this_transaction)).performClick()
        rule.waitUntil(timeoutMillis = 20_000) { transactions().none { it.id == occurrence.id } }
        waitForUndo()
        assertPlusClearOf(undo)

        rule.onNode(undo).performClick()
        rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == occurrence.id } }
        val restored = transactions().single { it.id == occurrence.id }
        assertEquals(0, BigDecimal("-12.50").compareTo(restored.amount))
        assertEquals(occurrence.recurrenceRuleId, restored.recurrenceRuleId)
    }

    /**
     * Regression guard for the snackbar plumbing (code review r1/r2): two deletes without resolving
     * the first Undo, then a save from +. Undo never expires (#376), so if Activity shared the
     * shell's queue, the queued second Undo would hold back "Transaction saved". Each delete keeps
     * its own Undo afterwards, as before #368.
     */
    @Test
    fun ac03_saveFromPlusAfterTwoDeletesStillConfirms_compact() {
        val coffee = seedExpense("coffee")
        val tea = seedExpense("tea")
        host(widthDp = 411)

        listOf("coffee" to coffee, "tea" to tea).forEach { (note, id) ->
            swipeLeftOn(note)
            rule.onNodeWithText(string(R.string.delete_transaction)).performClick()
            rule.waitUntil(timeoutMillis = 20_000) { transactions().none { it.id == id } }
            waitForUndo()
        }
        rule.onAllNodes(undo).assertCountEquals(1)

        // Activity's search box is a text field too: the amount is the editor's first new field.
        val before = rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().map { it.id }.toSet()
        rule.onNode(plus).performClick()
        rule.waitForIdle()
        val amount = rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().first { it.id !in before }.id
        rule.onNode(SemanticsMatcher("id $amount") { it.id == amount }).performTextInput("3.00")
        rule.waitForIdle()
        val save = hasContentDescription(string(R.string.add_transaction)) and hasClickAction()
        rule.onNode(save).assertIsEnabled()
        rule.mainClock.autoAdvance = false
        try {
            rule.onNode(save).performClick()
            val saved = hasText(string(R.string.transaction_saved))
            val deadline = System.currentTimeMillis() + 60_000
            while (rule.onAllNodes(saved).fetchSemanticsNodes().isEmpty() && System.currentTimeMillis() < deadline) {
                rule.mainClock.advanceTimeByFrame()
                Thread.sleep(16)
            }
            assertTrue(
                "'Transaction saved' never showed: stored=${transactions().map { it.amount }}, " +
                    "undo showing=${rule.onAllNodes(undo).fetchSemanticsNodes().size}",
                rule.onAllNodes(saved).fetchSemanticsNodes().isNotEmpty(),
            )
        } finally {
            rule.mainClock.autoAdvance = true
        }
        assertEquals(listOf(0), transactions().map { BigDecimal("-3.00").compareTo(it.amount) })

        // Neither earlier Undo was discarded: each still restores its own row, in order.
        listOf(coffee, tea).forEach { id ->
            waitForUndo()
            rule.onNode(undo).performClick()
            rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == id } }
        }
        assertEquals(3, transactions().size)
    }

    /**
     * Step-7 evidence: the delete-Undo snackbar on a phone in every cell the AC cares about. It
     * asserts only that the + is clear of Undo; the PNG and semantics dump are for the visual
     * review. Pull them from `ui-delete-undo/` (see the skill's `references/parity-tests.md`).
     */
    @Test
    fun captureDeleteUndoSnackbar() {
        val cells = listOf(
            CaptureHarness.Cell("en-light-compact"),
            CaptureHarness.Cell("it-light-compact", locale = Locale.ITALIAN),
            CaptureHarness.Cell("en-dark-compact", theme = ThemeMode.DARK),
            CaptureHarness.Cell("it-dark-compact", locale = Locale.ITALIAN, theme = ThemeMode.DARK),
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
        val outputDir = CaptureHarness.outputDir("ui-delete-undo")
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val originalConfiguration = Configuration(app.resources.configuration)
        try {
            cells.forEach { c -> captureCell(c, cell, outputDir, base) }
        } finally {
            setApplicationResourcesLocale(originalConfiguration)
        }
    }

    /**
     * Activity builds its snackbar copy with `application.getString` (ActivityScreen.kt:299), which
     * the harness's composition-local locale never reaches. So the application's own resources take
     * the cell's locale too; the per-cell wait below then requires the localized message.
     */
    @Suppress("DEPRECATION")
    private fun setApplicationResourcesLocale(configuration: Configuration) {
        app.resources.updateConfiguration(configuration, app.resources.displayMetrics)
    }

    private fun captureCell(
        c: CaptureHarness.Cell,
        cell: androidx.compose.runtime.MutableState<CaptureHarness.Cell>,
        outputDir: java.io.File,
        base: android.content.Context,
    ) {
        setApplicationResourcesLocale(
            Configuration(base.resources.configuration).apply { setLocale(c.locale ?: Locale.ENGLISH) },
        )
        run {
            val id = seedCoffee()
            cell.value = c
            rule.waitForIdle()
            val localized = CaptureHarness.localeContext(base, c.locale)
            with(NavShellMarkers(c.locale)) { rule.selectTab(activityTab) }
            swipeCoffeeLeft()
            // The dialog is its own window, which may keep the device language (see SaveFeedbackTest).
            // `base` shares the application's (now re-localized) resources: name English explicitly.
            val confirm = (
                hasText(CaptureHarness.localeContext(base, Locale.ENGLISH).getString(R.string.delete_transaction)) or
                    hasText(localized.getString(R.string.delete_transaction))
                ) and hasClickAction() and hasAnyAncestor(isDialog())
            rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(confirm).fetchSemanticsNodes().isNotEmpty() }
            rule.onNode(confirm).performClick()
            try {
                rule.waitUntil(timeoutMillis = 20_000) { transactions().none { it.id == id } }
            } catch (e: ComposeTimeoutException) {
                // The CI artifact carries no device files: put the evidence in the failure itself.
                throw AssertionError(
                    "${c.id}: delete never landed; stored=${transactions().map { it.note }}\n" +
                        rule.onAllNodes(isRoot()).printToString(maxDepth = Int.MAX_VALUE),
                    e,
                )
            }
            // Both the message and the action in the cell's language, or the cell is not evidence.
            val localizedUndo = hasText(localized.getString(R.string.undo)) and hasClickAction()
            val localizedMessage = hasText(localized.getString(R.string.transaction_deleted))
            try {
                rule.waitUntil(timeoutMillis = 20_000) {
                    rule.onAllNodes(localizedUndo).fetchSemanticsNodes().isNotEmpty() &&
                        rule.onAllNodes(localizedMessage).fetchSemanticsNodes().isNotEmpty()
                }
            } catch (e: Throwable) {
                CaptureHarness.writeSemantics(rule, outputDir, "${c.id}-timeout")
                throw AssertionError("${c.id}: localized snackbar never showed", e)
            }
            rule.waitForIdle()
            val plusNode = hasContentDescription(localized.getString(R.string.add_transaction)) and hasClickAction()
            val undoBounds = rule.onNode(localizedUndo).fetchSemanticsNode().boundsInWindow
            val plusBounds = rule.onNode(plusNode).fetchSemanticsNode().boundsInWindow
            assertTrue("${c.id}: Undo $undoBounds covered by + $plusBounds", !plusBounds.overlaps(undoBounds))
            CaptureHarness.writePng(rule, outputDir, c.id)
            CaptureHarness.writeSemantics(rule, outputDir, c.id)
            // Restore so the next cell starts from the same single row; the Undo is indefinite (#376).
            rule.onNode(localizedUndo).performClick()
            rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == id } }
            runBlocking { app.database.clearAllTables(); app.categoryRepository.seedDefaultsIfEmpty() }
            // Let the row leave the screen before the next cell seeds another "coffee": a row keeps
            // the swipe callback of the transaction it was first composed for (#386), so a reused
            // slot would open the dialog for this cell's, already-gone, transaction.
            rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText("coffee")).fetchSemanticsNodes().isEmpty() }
        }
    }
}
