package com.rizzog99.personalfinancetracker.navigation

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
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
 * #376: Activity's "Transaction deleted · Undo" goes away by itself after 5 s, as frozen iOS's banner
 * does (`TransactionListViewModel.swift:548`, `b649dfff`), and the delete stays done.
 *
 * Hosts the production [PersonalFinanceNavHost] like [ActivityUndoPlacementTest]. Time on screen is
 * the compose test clock: frozen right after the delete is confirmed, then stepped by hand, so an
 * idle sync can never jump past (or short of) the window.
 */
@RunWith(AndroidJUnit4::class)
class ActivityUndoTimeoutTest {

    @get:Rule
    val rule = createComposeRule()

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val app: PersonalFinanceApplication
        get() = context.applicationContext as PersonalFinanceApplication

    private fun string(id: Int): String = context.getString(id)

    private fun transactions(): List<FinanceTransaction> =
        runBlocking { app.transactionRepository.observeAll().first() }

    private val undo: SemanticsMatcher
        get() = hasText(string(R.string.undo)) and hasClickAction()

    private fun undoShowing() = rule.onAllNodes(undo).fetchSemanticsNodes().isNotEmpty()

    @Before
    fun emptyLedgerAndNoTimeoutExtension() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        assertEquals("precondition: empty ledger", 0, transactions().size)
        // The 5 s below holds only while no accessibility setting extends it (D-01 on #376).
        val a11y = context.getSystemService(AccessibilityManager::class.java)
        if (Build.VERSION.SDK_INT >= 29) {
            assertEquals(
                "precondition: no 'Time to take action' extension on this device",
                5_000,
                a11y.getRecommendedTimeoutMillis(
                    5_000,
                    AccessibilityManager.FLAG_CONTENT_TEXT or AccessibilityManager.FLAG_CONTENT_CONTROLS,
                ),
            )
        } else {
            assertTrue("precondition: TalkBack off", !a11y.isTouchExplorationEnabled)
        }
    }

    @After
    fun restoreClock() {
        rule.mainClock.autoAdvance = true
    }

    private fun groceries() = runBlocking {
        app.categoryRepository.observeAll().first()
            .first { it.name == "Groceries" && it.type == TransactionType.EXPENSE }
    }

    /** One −12.50 EUR one-off expense in Groceries; returns its id. */
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

    /**
     * Swipes [note]'s row and taps [confirm] with the clock running, then freezes the clock and steps
     * it a frame at a time until the row has left Room and an Undo shows. The Room write runs in real
     * time, hence the wall-clock deadline; the time on screen is only what [advance] adds after this.
     */
    private fun deleteAndFreezeOnUndo(note: String, id: String, confirm: Int = R.string.delete_transaction) {
        rule.mainClock.autoAdvance = true
        rule.onNodeWithText(note).performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithText(string(confirm)).performClick()
        stepUntil("$note deleted and Undo shown") { transactions().none { it.id == id } && undoShowing() }
    }

    private fun stepUntil(what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 60_000
        while (!condition() && System.currentTimeMillis() < deadline) {
            rule.mainClock.advanceTimeByFrame()
            Thread.sleep(16)
        }
        assertTrue("never: $what", condition())
    }

    private fun advance(millis: Long) {
        rule.mainClock.advanceTimeBy(millis)
        rule.waitForIdle()
    }

    private fun undoNodeId(): Int = rule.onNode(undo).fetchSemanticsNode().id

    /**
     * The Undo that showed at virtual time [shownAt] is still up just before 5 s (so not Material's
     * 4 s Short) and gone by 5 s plus [EXIT_TOLERANCE_MS] (a frame to start the timer, the exit fade).
     */
    private fun assertUndoLastsFiveSeconds(shownAt: Long) {
        advance(shownAt + 4_900 - rule.mainClock.currentTime)
        assertTrue("Undo gone before 5 s", undoShowing())
        stepUntil("Undo gone") { !undoShowing() }
        val lifetime = rule.mainClock.currentTime - shownAt
        assertTrue("Undo lasted $lifetime ms", lifetime <= 5_000 + EXIT_TOLERANCE_MS)
    }

    private fun assertExpiresAndStaysDeleted(widthDp: Int) {
        val id = seedExpense("coffee")
        host(widthDp)

        deleteAndFreezeOnUndo("coffee", id)
        assertUndoLastsFiveSeconds(shownAt = rule.mainClock.currentTime)

        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        assertTrue("the delete was reverted", transactions().none { it.id == id })
        rule.onAllNodes(hasText("coffee")).assertCountEquals(0)
    }

    @Test
    fun ac01_undoExpiresAfterFiveSeconds_compact() = assertExpiresAndStaysDeleted(widthDp = 411)

    @Test
    fun ac02_undoWithinWindowRestores_compact() {
        val id = seedExpense("coffee")
        host(widthDp = 411)

        deleteAndFreezeOnUndo("coffee", id)
        advance(4_000)
        rule.onNode(undo).performClick()
        rule.mainClock.autoAdvance = true
        rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == id } }
        assertEquals(0, BigDecimal("-12.50").compareTo(transactions().single { it.id == id }.amount))
        rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText("coffee")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("coffee").assertIsDisplayed()
    }

    @Test
    fun ac03_secondDeleteGetsItsOwnFullWindow_compact() {
        val coffee = seedExpense("coffee")
        val tea = seedExpense("tea")
        host(widthDp = 411)

        deleteAndFreezeOnUndo("coffee", coffee)
        val coffeeShownAt = rule.mainClock.currentTime
        val coffeeUndo = undoNodeId()
        // Tea's delete queues behind coffee's Undo: one snackbar at a time.
        rule.mainClock.autoAdvance = true
        rule.onNodeWithText("tea").performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
        assertTrue("coffee's Undo expired during the second swipe; the setup is not evidence", undoShowing())
        rule.onNodeWithText(string(R.string.delete_transaction)).performClick()
        stepUntil("tea deleted") { transactions().none { it.id == tea } }
        rule.onAllNodes(undo).assertCountEquals(1)

        // Coffee's window ends on time, and tea's Undo takes its place with a full window of its own.
        // During the cross-fade both snackbars have nodes; tea's is the only one left afterwards. A
        // frame with none also counts as the handoff, in case the new snackbar reuses the node id.
        var sawGap = false
        stepUntil("tea's Undo replaced coffee's") {
            val nodes = rule.onAllNodes(undo).fetchSemanticsNodes()
            if (nodes.isEmpty()) sawGap = true
            nodes.size == 1 && (sawGap || nodes.single().id != coffeeUndo)
        }
        val teaShownAt = rule.mainClock.currentTime
        assertTrue(
            "tea's Undo came ${teaShownAt - coffeeShownAt} ms after coffee's",
            teaShownAt - coffeeShownAt <= 5_000 + EXIT_TOLERANCE_MS,
        )
        advance(teaShownAt + 4_500 - rule.mainClock.currentTime)
        assertTrue("tea's Undo did not get its full window", undoShowing())

        rule.onNode(undo).performClick()
        rule.mainClock.autoAdvance = true
        rule.waitUntil(timeoutMillis = 20_000) { transactions().any { it.id == tea } }
        assertTrue("coffee came back", transactions().none { it.id == coffee })
    }

    @Test
    fun ac04_recurringThisOnlyUndoExpires_compact() {
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

        deleteAndFreezeOnUndo("coffee", occurrence.id, confirm = R.string.delete_this_transaction)
        assertUndoLastsFiveSeconds(shownAt = rule.mainClock.currentTime)

        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        assertTrue("the occurrence was restored", transactions().none { it.id == occurrence.id })
    }

    @Test
    fun ac05_undoExpiresAfterFiveSeconds_wide() = assertExpiresAndStaysDeleted(widthDp = 900)

    private companion object {
        /** A frame or two for the timer to see the snackbar, plus Material's exit fade. */
        const val EXIT_TOLERANCE_MS = 400L
    }
}
