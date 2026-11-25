package com.rizzog99.personalfinancetracker.navigation

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.local.RecurrenceRuleEntity
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ACTIVITY_SEARCH_TAG
import com.rizzog99.personalfinancetracker.features.activity.BULK_ACTION_BAR_TAG
import com.rizzog99.personalfinancetracker.features.activity.BULK_INPUT_TAG
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #285 Activity multi-select, bulk edits and Undo, driven through the production
 * [PersonalFinanceNavHost] like [ActivityUndoTimeoutTest].
 *
 * Fixture F (issue #285): t1 "Caffè bar" −3.00 Coffee & Drinks; t2 "Caffè casa" −12.50 Groceries,
 * goal; t3 "Netflix" −9.99 Streaming Services, rule r1; t4 "Stipendio" +1500.00 Salary.
 */
@RunWith(AndroidJUnit4::class)
class ActivityBulkSelectionTest {

    @get:Rule
    val rule = createComposeRule()

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val app: PersonalFinanceApplication
        get() = context.applicationContext as PersonalFinanceApplication

    private fun string(id: Int): String = context.getString(id)
    private fun plural(id: Int, n: Int): String = context.resources.getQuantityString(id, n, n)

    private lateinit var fixture: List<FinanceTransaction>
    private val markers = NavShellMarkers()

    private fun stored(): Map<String, FinanceTransaction> =
        runBlocking { app.transactionRepository.observeAll().first() }.associateBy { it.id }

    private fun category(name: String, type: TransactionType): FinanceCategory = runBlocking { app.category(name, type) }

    @Before
    fun seedFixture() = runBlocking {
        fixture = seedBulkFixture(app)
        assertEquals("precondition: fixture stored", fixture.map { it.id }.toSet(), stored().keys)
    }

    private fun host(widthDp: Int = 411) {
        rule.setContent {
            val configuration = Configuration(LocalContext.current.resources.configuration).apply { screenWidthDp = widthDp }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) { ForcedWidth(widthDp) { PersonalFinanceNavHost() } }
            }
        }
        rule.waitForIdle()
        with(markers) { rule.selectTab(activityTab) }
        // The top row: a lazy list composes only what fits, and a squeezed wide host fits little.
        awaitText("Caffè bar")
    }

    private fun awaitText(text: String) =
        rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty() }

    private fun awaitGone(text: String) =
        rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText(text)).fetchSemanticsNodes().isEmpty() }

    private fun awaitStored(what: String, condition: (Map<String, FinanceTransaction>) -> Boolean) {
        rule.waitUntil(timeoutMillis = 20_000) { condition(stored()) }
    }

    private fun longPress(note: String) {
        rule.onNodeWithText(note).performScrollTo().performTouchInput { longClick() }
        rule.waitForIdle()
    }

    /** A selection-mode row: the merged toggleable node holding [note]. */
    private fun selectable(note: String): SemanticsMatcher = isToggleable() and hasText(note, substring = true)

    private fun tap(note: String) {
        rule.onNode(selectable(note)).performScrollTo().performClick()
        rule.waitForIdle()
    }

    private fun bulkAction(label: Int) {
        rule.onNode(hasText(string(label)) and hasClickAction() and hasAnyAncestor(hasTestTag(BULK_ACTION_BAR_TAG))).performClick()
        rule.waitForIdle()
        if (label == R.string.bulk_amount || label == R.string.bulk_description) {
            rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasTestTag(BULK_INPUT_TAG)).fetchSemanticsNodes().isNotEmpty() }
        }
    }

    private fun undo() {
        rule.onNode(hasText(string(R.string.undo)) and hasClickAction()).performClick()
        rule.waitForIdle()
    }

    private fun FinanceTransaction.sameAs(expected: FinanceTransaction) =
        expected.amount.compareTo(amount) == 0 && expected.copy(amount = amount) == this

    private fun assertFixtureRestored() = awaitStored("fixture restored") { s -> fixture.all { s[it.id]?.sameAs(it) == true } }

    @Test
    fun ac01_longPressSelectAllAndPrune_compact() {
        host()
        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("caffè")
        awaitGone("Stipendio")

        longPress("Caffè bar")
        awaitText(plural(R.plurals.selection_count, 1))
        rule.onAllNodes(markers.tab(markers.activityTab)).assertCountEquals(0)
        rule.onAllNodes(hasContentDescription(string(R.string.add_transaction))).assertCountEquals(0)

        rule.onNode(hasContentDescription(string(R.string.select_all)) and hasClickAction()).performClick()
        awaitText(plural(R.plurals.selection_count, 2))
        rule.onNode(hasContentDescription(string(R.string.deselect_all)) and hasClickAction()).assertIsEnabled()
        listOf("Caffè bar", "Caffè casa").forEach {
            rule.onNode(selectable(it)).assertToggle(ToggleableState.On)
        }

        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("caffè bar")
        awaitText(plural(R.plurals.selection_count, 1))

        // Back first closes the keyboard; only then does it reach selection mode.
        Espresso.closeSoftKeyboard()
        rule.waitForIdle()
        Espresso.pressBack()
        awaitNavBack()
        rule.onAllNodes(isToggleable() and hasText("Caffè bar", substring = true)).assertCountEquals(0)

        // Cancel leaves selection mode too.
        longPress("Caffè bar")
        awaitText(plural(R.plurals.selection_count, 1))
        rule.onNode(hasContentDescription(string(R.string.cancel)) and hasClickAction()).performClick()
        awaitNavBack()
        assertEquals(fixture.map { it.id }.toSet(), stored().keys)
    }

    private fun awaitNavBack() = rule.waitUntil(timeoutMillis = 20_000) {
        rule.onAllNodes(markers.tab(markers.activityTab)).fetchSemanticsNodes().isNotEmpty()
    }

    @Test
    fun ac04_secondBulkActionReplacesPendingUndo_compact() {
        host()
        longPress("Caffè bar")
        tap("Stipendio")
        awaitText(plural(R.plurals.selection_count, 2))
        bulkAction(R.string.bulk_amount)
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("20")
        rule.onNode(hasText(string(R.string.bulk_set)) and hasClickAction()).performClick()
        awaitText(plural(R.plurals.transactions_updated, 2))
        awaitStored("amount applied") { s -> s.getValue("t1").amount.compareTo(BigDecimal("-20")) == 0 }

        longPress("Caffè bar")
        tap("Caffè casa")
        awaitText(plural(R.plurals.selection_count, 2))
        bulkAction(R.string.bulk_description)
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("Spesa")
        rule.onNode(hasText(string(R.string.bulk_set)) and hasClickAction()).performClick()
        awaitStored("note applied") { s -> s.getValue("t1").note == "Spesa" && s.getValue("t2").note == "Spesa" }
        rule.waitUntil(timeoutMillis = 20_000) {
            rule.onAllNodes(hasText(string(R.string.undo)) and hasClickAction()).fetchSemanticsNodes().size == 1
        }
        undo()
        awaitStored("only the description undone") { s ->
            s.getValue("t1").note == "Caffè bar" && s.getValue("t2").note == "Caffè casa" &&
                s.getValue("t1").amount.compareTo(BigDecimal("-20")) == 0 && s.getValue("t4").amount.compareTo(BigDecimal("20")) == 0
        }
        // Nothing queued behind it brings the amounts back.
        Thread.sleep(6_000)
        assertEquals(0, stored().getValue("t4").amount.compareTo(BigDecimal("20")))
    }

    @Test
    fun ac02_bulkCategoryAndUndo_compact() {
        host()
        longPress("Caffè bar")
        tap("Caffè casa")
        awaitText(plural(R.plurals.selection_count, 2))

        bulkAction(R.string.bulk_category)
        // The grid is lazy, and Salary sits past the first tiles: search for it, as a user would.
        rule.waitUntil(timeoutMillis = 20_000) {
            rule.onAllNodes(hasSetTextAction() and hasText(string(R.string.search_categories))).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNode(hasSetTextAction() and hasText(string(R.string.search_categories))).performTextReplacement("Salary")
        rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText("Salary") and hasClickAction() and !hasSetTextAction()).fetchSemanticsNodes().isNotEmpty() }
        rule.onAllNodes(hasText("Salary") and hasClickAction() and !hasSetTextAction()).onFirst().performClick()
        awaitText(plural(R.plurals.transactions_updated, 2))
        val salary = category("Salary", TransactionType.INCOME)
        awaitStored("category applied") { s ->
            s.getValue("t1").amount.compareTo(BigDecimal("3.00")) == 0 &&
                s.getValue("t2").amount.compareTo(BigDecimal("12.50")) == 0 &&
                listOf("t1", "t2").all { s.getValue(it).categoryId == salary.id && s.getValue(it).categoryLabel == "Salary" } &&
                s.getValue("t2").goalId == null
        }

        undo()
        assertFixtureRestored()
    }

    @Test
    fun ac03_bulkDeleteAndUndo_compact() {
        host()
        longPress("Caffè bar")
        tap("Caffè casa")
        tap("Netflix")
        awaitText(plural(R.plurals.selection_count, 3))

        bulkAction(R.string.bulk_delete)
        awaitText(plural(R.plurals.transactions_deleted, 3))
        awaitStored("three deleted") { it.keys == setOf("t4") }
        awaitGone("Netflix")
        val rule1 = runBlocking { app.database.recurrenceRuleDao().get("r1") }
        assertNotNull("the rule survives", rule1)
        assertNull("the rule is not closed", rule1!!.endDateEpochMillis)

        undo()
        assertFixtureRestored()
        awaitText("Netflix")
    }

    @Test
    fun ac04_bulkAmountAndDescription_compact() {
        host()
        longPress("Caffè bar")
        tap("Stipendio")
        awaitText(plural(R.plurals.selection_count, 2))

        bulkAction(R.string.bulk_amount)
        awaitText(string(R.string.bulk_new_amount))
        val set = hasText(string(R.string.bulk_set)) and hasClickAction()
        rule.onNode(set).assertIsNotEnabled()
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("0")
        rule.onNode(set).assertIsNotEnabled()
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("20")
        rule.onNode(set).assertIsEnabled().performClick()
        awaitText(plural(R.plurals.transactions_updated, 2))
        awaitStored("amount applied") { s ->
            s.getValue("t1").amount.compareTo(BigDecimal("-20")) == 0 && s.getValue("t4").amount.compareTo(BigDecimal("20")) == 0
        }
        undo()
        assertFixtureRestored()

        longPress("Caffè bar")
        tap("Caffè casa")
        awaitText(plural(R.plurals.selection_count, 2))
        bulkAction(R.string.bulk_description)
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("Spesa")
        rule.onNode(set).performClick()
        awaitStored("note applied") { s -> s.getValue("t1").note == "Spesa" && s.getValue("t2").note == "Spesa" }
        undo()
        assertFixtureRestored()
    }

    /** R8: a bulk Undo still queued behind another snackbar is dropped by a later mutation. */
    @Test
    fun ac04_queuedBulkUndoIsDroppedByALaterMutation_compact() = withUndoWindowOf(seconds = 15) {
        host()
        rule.onNodeWithText("Netflix").performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
        rule.onNodeWithText(string(R.string.delete_this_transaction)).performClick()
        awaitStored("t3 deleted") { "t3" !in it }

        longPress("Caffè bar")
        tap("Stipendio")
        awaitText(plural(R.plurals.selection_count, 2))
        bulkAction(R.string.bulk_amount)
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("20")
        rule.onNode(hasText(string(R.string.bulk_set)) and hasClickAction()).performClick()
        awaitStored("amount applied") { s -> s.getValue("t4").amount.compareTo(BigDecimal("20")) == 0 }

        longPress("Caffè bar")
        tap("Caffè casa")
        awaitText(plural(R.plurals.selection_count, 2))
        bulkAction(R.string.bulk_description)
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("Spesa")
        rule.onNode(hasText(string(R.string.bulk_set)) and hasClickAction()).performClick()
        awaitStored("note applied") { s -> s.getValue("t2").note == "Spesa" }
        // Both bulk Undos were queued behind t3's single one, or this test proves nothing.
        assertTrue(
            "t3's Undo expired during setup; the setup is not evidence",
            rule.onAllNodes(hasText(string(R.string.transaction_deleted))).fetchSemanticsNodes().isNotEmpty(),
        )

        // t3's single Undo runs out; the description's Undo is the only bulk one left.
        rule.waitUntil(timeoutMillis = 40_000) {
            rule.onAllNodes(hasText(plural(R.plurals.transactions_updated, 2))).fetchSemanticsNodes().isNotEmpty()
        }
        undo()
        awaitStored("only the description undone") { s ->
            s.getValue("t1").note == "Caffè bar" && s.getValue("t2").note == "Caffè casa" &&
                s.getValue("t1").amount.compareTo(BigDecimal("-20")) == 0 && s.getValue("t4").amount.compareTo(BigDecimal("20")) == 0
        }
        Thread.sleep(6_000)
        rule.onAllNodes(hasText(string(R.string.undo)) and hasClickAction()).assertCountEquals(0)
        assertEquals(0, stored().getValue("t4").amount.compareTo(BigDecimal("20")))
    }

    /**
     * Runs [block] with Android's "Time to take action" set to [seconds], which every Activity Undo honours
     * (#376 D-01), so a multi-step setup cannot outlive the first Undo on a loaded emulator. Always
     * restored: the #376 timing tests assert the setting is off.
     */
    private fun withUndoWindowOf(seconds: Int, block: () -> Unit) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun shell(command: String) = automation.executeShellCommand(command).use { pfd ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(pfd).bufferedReader().readText().trim()
        }
        val before = shell("settings get secure accessibility_interactive_ui_timeout_ms")
        shell("settings put secure accessibility_interactive_ui_timeout_ms ${seconds * 1_000}")
        try {
            block()
        } finally {
            if (before == "null" || before.isEmpty()) {
                shell("settings delete secure accessibility_interactive_ui_timeout_ms")
            } else {
                shell("settings put secure accessibility_interactive_ui_timeout_ms $before")
            }
        }
    }

    @Test
    fun ac05_selectionSemantics_compact() {
        host()
        longPress("Caffè bar")
        awaitText(plural(R.plurals.selection_count, 1))
        rule.onNode(hasText(plural(R.plurals.selection_count, 1)))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))

        // One toggle target per row, merged: role, state and the recurring badge on the same node.
        rule.onAllNodes(selectable("Netflix")).assertCountEquals(1)
        val netflix = rule.onNode(selectable("Netflix"))
        netflix.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Checkbox))
        netflix.assertToggle(ToggleableState.Off)
        rule.onNode(selectable("Netflix") and hasContentDescription(string(R.string.recurring_badge), substring = true)).assertExists()
        tap("Netflix")
        rule.onNode(selectable("Netflix")).assertToggle(ToggleableState.On)
    }

    @Test
    fun ac06_wideSelectionDeleteUndo() {
        host(widthDp = 900)
        // The rail's + is one of these; the two-pane editor has its own.
        val adds = rule.onAllNodes(hasContentDescription(string(R.string.add_transaction))).fetchSemanticsNodes().size
        longPress("Caffè bar")
        awaitText(plural(R.plurals.selection_count, 1))
        rule.onNode(markers.tab(markers.activityTab)).assertExists()
        rule.onAllNodes(hasContentDescription(string(R.string.add_transaction))).assertCountEquals(adds - 1)
        rule.onNode(hasContentDescription(string(R.string.select_all)) and hasClickAction()).performClick()
        awaitText(plural(R.plurals.selection_count, 4))

        bulkAction(R.string.bulk_delete)
        awaitText(plural(R.plurals.transactions_deleted, 4))
        awaitStored("all deleted") { it.isEmpty() }
        undo()
        assertFixtureRestored()
    }

    @Test
    fun ac06_tapAndSwipeUnchangedOutsideSelection_compact() {
        host()
        rule.onAllNodes(isToggleable() and hasText("Caffè bar", substring = true)).assertCountEquals(0)
        // A tap still opens the editor on that row, with no selection mode.
        rule.onNodeWithText("Caffè bar").performScrollTo().performClick()
        awaitText(string(R.string.edit_transaction))
        rule.onAllNodes(hasText(plural(R.plurals.selection_count, 1))).assertCountEquals(0)
        Espresso.closeSoftKeyboard()
        Espresso.pressBack()
        rule.waitUntil(timeoutMillis = 20_000) { rule.onAllNodes(hasText(string(R.string.edit_transaction))).fetchSemanticsNodes().isEmpty() }
        rule.onNodeWithText("Caffè bar").performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
        rule.onNodeWithText(string(R.string.delete_transaction_confirmation_title)).assertExists()
        rule.onNodeWithText(string(R.string.cancel)).performClick()
        rule.waitForIdle()
        assertEquals(fixture.map { it.id }.toSet(), stored().keys)
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertToggle(state: ToggleableState) =
        assert(SemanticsMatcher.expectValue(SemanticsProperties.ToggleableState, state))
}

private suspend fun PersonalFinanceApplication.category(name: String, type: TransactionType): FinanceCategory =
    categoryRepository.observeAll().first().first { it.name == name && it.type == type }

/** Fixture F of #285 on a clean store; shared with `ActivityBulkSelectionCaptureTest`. Returns t1..t4. */
internal suspend fun seedBulkFixture(app: PersonalFinanceApplication): List<FinanceTransaction> {
    app.database.clearAllTables()
    app.categoryRepository.seedDefaultsIfEmpty()
    val goal = app.goalRepository.add(NewGoal(name = "Holiday", targetAmount = BigDecimal("500"))).id
    app.database.recurrenceRuleDao().insert(
        RecurrenceRuleEntity(
            id = "r1", frequency = "MONTHLY", interval = 1,
            startDateEpochMillis = Instant.parse("2026-01-12T10:00:00Z").toEpochMilli(), endDateEpochMillis = null,
            lastMaterializedDateEpochMillis = Instant.parse("2026-03-12T10:00:00Z").toEpochMilli(),
            amountDecimal = "-9.99", note = "Netflix", categoryLabel = "Streaming Services", categoryId = null,
            currencyCode = "EUR", goalId = null, autoRecord = false,
        ),
    )
    fun row(id: String, date: String, note: String, amount: String, category: FinanceCategory, goal: String? = null, rule: String? = null) =
        FinanceTransaction(
            id = id, timestamp = Instant.parse("${date}T10:00:00Z"), amount = BigDecimal(amount), note = note,
            categoryLabel = category.name, categoryId = category.id, currencyCode = "EUR", goalId = goal, recurrenceRuleId = rule,
        )
    val fixture = listOf(
        row("t1", "2026-03-14", "Caffè bar", "-3.00", app.category("Coffee & Drinks", TransactionType.EXPENSE)),
        row("t2", "2026-03-13", "Caffè casa", "-12.50", app.category("Groceries", TransactionType.EXPENSE), goal = goal),
        row("t3", "2026-03-12", "Netflix", "-9.99", app.category("Streaming Services", TransactionType.EXPENSE), rule = "r1"),
        row("t4", "2026-03-10", "Stipendio", "1500.00", app.category("Salary", TransactionType.INCOME)),
    )
    app.transactionRepository.upsertAll(fixture)
    return fixture
}
