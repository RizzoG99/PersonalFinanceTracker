package com.rizzog99.personalfinancetracker.navigation

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.isEnabled
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
import org.junit.After
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

    private fun undoShowing() =
        rule.onAllNodes(hasText(string(R.string.transaction_deleted))).fetchSemanticsNodes().isNotEmpty() &&
            rule.onAllNodes(undo).fetchSemanticsNodes().isNotEmpty()

    /** Steps the frozen clock a frame at a time; the wall-clock deadline is for Room's real-time writes. */
    private fun stepUntil(what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 60_000
        while (!condition() && System.currentTimeMillis() < deadline) {
            rule.mainClock.advanceTimeByFrame()
            Thread.sleep(16)
        }
        assertTrue("never: $what", condition())
    }

    /**
     * Taps [confirm] and freezes the clock until [id] has left Room and Undo shows. Undo lasts 5 s
     * (#376): under auto-advance, a wait on a slow emulator could run the virtual clock past it.
     */
    private fun confirmDeleteAndFreezeOnUndo(id: String, confirm: Int = R.string.delete_transaction) {
        rule.mainClock.autoAdvance = false
        rule.onNodeWithText(string(confirm)).performClick()
        stepUntil("deleted and Undo shown") { transactions().none { it.id == id } && undoShowing() }
        rule.mainClock.advanceTimeBy(500) // past the enter animation, well inside the 5 s window
    }

    @After
    fun restoreClock() {
        rule.mainClock.autoAdvance = true
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
        confirmDeleteAndFreezeOnUndo(id)
        assertPlusClearOf(undo)

        rule.onNode(undo).performClick()
        rule.mainClock.autoAdvance = true
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
        confirmDeleteAndFreezeOnUndo(occurrence.id, confirm = R.string.delete_this_transaction)
        assertPlusClearOf(undo)

        rule.onNode(undo).performClick()
        rule.mainClock.autoAdvance = true
        rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == occurrence.id } }
        val restored = transactions().single { it.id == occurrence.id }
        assertEquals(0, BigDecimal("-12.50").compareTo(restored.amount))
        assertEquals(occurrence.recurrenceRuleId, restored.recurrenceRuleId)
    }

    /**
     * Regression guard for the snackbar plumbing (code review r1/r2): two deletes without resolving
     * the first Undo, then a save from +. If Activity shared the shell's queue, the queued Undos would
     * hold back "Transaction saved" for up to 5 s each (#376). So the clock stays frozen from the
     * deletes through the save, and "Transaction saved" must show while an Undo is still up: only two
     * queues can show both at once. The queued second Undo still works afterwards, as before #368.
     */
    @Test
    fun ac03_saveFromPlusAfterTwoDeletesStillConfirms_compact() {
        val coffee = seedExpense("coffee")
        val tea = seedExpense("tea")
        host(widthDp = 411)

        swipeLeftOn("coffee")
        confirmDeleteAndFreezeOnUndo(coffee)
        rule.mainClock.autoAdvance = true // the swipe needs running frames: a few hundred ms of window
        swipeLeftOn("tea")
        confirmDeleteAndFreezeOnUndo(tea)
        rule.onAllNodes(undo).assertCountEquals(1)

        // Activity's search box is a text field too: the amount is the editor's first new field.
        val before = rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().map { it.id }.toSet()
        val fab = rule.onNode(plus).fetchSemanticsNode().id
        rule.onNode(plus).performClick()
        stepUntil("editor open") { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().any { it.id !in before } }
        val amount = rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().first { it.id !in before }.id
        rule.onNode(SemanticsMatcher("id $amount") { it.id == amount }).performTextInput("3.00")
        // The editor's save button shares the +'s label, and on a frozen clock the + may not have left
        // yet: the save button is the one that is not the +.
        val save = hasContentDescription(string(R.string.add_transaction)) and hasClickAction() and
            SemanticsMatcher("not the +") { it.id != fab }
        stepUntil("save enabled") { rule.onAllNodes(save and isEnabled()).fetchSemanticsNodes().size == 1 }
        assertTrue("precondition: an Activity Undo is still up at save", undoShowing())
        rule.onNode(save).performClick()
        val saved = hasText(string(R.string.transaction_saved))
        var undoAlongside = false
        stepUntil("'Transaction saved' shown") {
            val shown = rule.onAllNodes(saved).fetchSemanticsNodes().isNotEmpty()
            if (shown) undoAlongside = undoShowing()
            shown
        }
        assertTrue("'Transaction saved' waited behind Activity's Undo", undoAlongside)
        assertEquals(listOf(0), transactions().map { BigDecimal("-3.00").compareTo(it.amount) })

        // Tea's Undo was not discarded: queued behind coffee's, its window starts when it shows, so it
        // still restores tea. Coffee's may have run out during the editor flow (5 s, #376); if it is the
        // one still up, it restores coffee first.
        stepUntil("one Undo up") { rule.onAllNodes(undo).fetchSemanticsNodes().size == 1 }
        val firstUndo = rule.onNode(undo).fetchSemanticsNode().id
        rule.onNode(undo).performClick()
        stepUntil("a row restored") { transactions().any { it.id == coffee || it.id == tea } }
        if (transactions().none { it.id == tea }) {
            // The tapped one was coffee's; tea's is the next node, whenever the hand-off happened.
            val coffeeUndo = firstUndo
            stepUntil("tea's Undo up") {
                rule.onAllNodes(undo).fetchSemanticsNodes().let { it.size == 1 && it.single().id != coffeeUndo }
            }
            rule.onNode(undo).performClick()
            stepUntil("tea restored") { transactions().any { it.id == tea } }
        }
        assertTrue("tea restored", transactions().any { it.id == tea })
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
            // Frozen from the tap: the Undo lasts 5 s (#376), and an idle sync could run past it.
            rule.mainClock.autoAdvance = false
            rule.onNode(confirm).performClick()
            // Both the message and the action in the cell's language, or the cell is not evidence.
            val localizedUndo = hasText(localized.getString(R.string.undo)) and hasClickAction()
            val localizedMessage = hasText(localized.getString(R.string.transaction_deleted))
            try {
                stepUntil("${c.id}: delete landed and localized snackbar shown") {
                    transactions().none { it.id == id } &&
                        rule.onAllNodes(localizedUndo).fetchSemanticsNodes().isNotEmpty() &&
                        rule.onAllNodes(localizedMessage).fetchSemanticsNodes().isNotEmpty()
                }
            } catch (e: AssertionError) {
                // The CI artifact carries no device files: put the evidence in the failure itself.
                CaptureHarness.writeSemantics(rule, outputDir, "${c.id}-timeout")
                throw AssertionError(
                    "${c.id}: stored=${transactions().map { it.note }}\n" +
                        rule.onAllNodes(isRoot()).printToString(maxDepth = Int.MAX_VALUE),
                    e,
                )
            }
            rule.mainClock.advanceTimeBy(500) // past the enter animation, well inside the 5 s window
            val plusNode = hasContentDescription(localized.getString(R.string.add_transaction)) and hasClickAction()
            val undoBounds = rule.onNode(localizedUndo).fetchSemanticsNode().boundsInWindow
            val plusBounds = rule.onNode(plusNode).fetchSemanticsNode().boundsInWindow
            assertTrue("${c.id}: Undo $undoBounds covered by + $plusBounds", !plusBounds.overlaps(undoBounds))
            CaptureHarness.writePng(rule, outputDir, c.id)
            CaptureHarness.writeSemantics(rule, outputDir, c.id)
            // Restore so the next cell starts from the same single row, as before #376: the clock is still
            // frozen inside the 5 s window, so the Undo is there to tap.
            rule.onNode(localizedUndo).performClick()
            rule.mainClock.autoAdvance = true
            rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == id } }
            runBlocking { app.database.clearAllTables(); app.categoryRepository.seedDefaultsIfEmpty() }
            // Let the row leave the screen before the next cell seeds another "coffee": a row keeps
            // the swipe callback of the transaction it was first composed for (#386), so a reused
            // slot would open the dialog for this cell's, already-gone, transaction.
            rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText("coffee")).fetchSemanticsNodes().isEmpty() }
        }
    }
}
