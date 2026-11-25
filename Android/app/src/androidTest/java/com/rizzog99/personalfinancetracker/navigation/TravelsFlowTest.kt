package com.rizzog99.personalfinancetracker.navigation

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isSelected
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ACTIVITY_SEARCH_TAG
import com.rizzog99.personalfinancetracker.features.activity.BULK_ACTION_BAR_TAG
import com.rizzog99.personalfinancetracker.features.activity.BULK_INPUT_TAG
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #284 Travels, driven through the production [PersonalFinanceNavHost].
 *
 * Fixture T (issue #284): Barcellona = Hotel −250 (12 Sep), Taxi −30 (14 Sep), Rimborso +50 (16 Sep);
 * Caffè −3 (15 Sep) untagged; Risparmio −20 a goal transfer; Montagna an empty travel.
 */
@RunWith(AndroidJUnit4::class)
class TravelsFlowTest {

    @get:Rule
    val rule = createComposeRule()

    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val app: PersonalFinanceApplication get() = context.applicationContext as PersonalFinanceApplication
    private fun string(id: Int, vararg args: Any): String = context.getString(id, *args)
    private fun plural(id: Int, n: Int): String = context.resources.getQuantityString(id, n, n)
    private val markers = NavShellMarkers()

    private lateinit var barcellona: String

    private fun stored(): Map<String, FinanceTransaction> =
        runBlocking { app.transactionRepository.observeAll().first() }.associateBy { it.id }

    private fun travelNames(): List<String> = runBlocking { app.travelRepository.observeAll().first() }.map { it.name }

    @Before
    fun seed() = runBlocking {
        barcellona = seedTravelFixture(app)
        assertEquals("precondition: fixture", 5, stored().size)
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
        awaitText("Caffè")
    }

    private fun awaitText(text: String, substring: Boolean = false) = rule.waitUntil(20_000) {
        rule.onAllNodes(hasText(text, substring = substring)).fetchSemanticsNodes().isNotEmpty()
    }

    private fun awaitGone(matcher: SemanticsMatcher) = rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isEmpty() }

    private fun awaitStored(condition: (Map<String, FinanceTransaction>) -> Boolean) = try {
        rule.waitUntil(20_000) { condition(stored()) }
    } catch (e: Throwable) {
        throw AssertionError("stored tags: " + stored().mapValues { it.value.travelId }, e)
    }

    /** The collapsed travel row: one merged node described as "name, subtitle". */
    private fun travelRow(name: String) = hasContentDescription("$name, ", substring = true) and hasClickAction()

    private fun tapDescribed(description: Int) {
        rule.onNode(hasContentDescription(string(description)) and hasClickAction()).performClick()
        rule.waitForIdle()
    }

    /** A tappable text that is not a text field (the search box can hold the same word). */
    private fun tappable(text: String) = hasText(text) and hasClickAction() and !hasSetTextAction()

    private fun tapText(text: String) {
        rule.onNode(tappable(text)).performClick()
        rule.waitForIdle()
    }

    /** A travel chip in the editor: it carries a selected state, unlike the list row behind the sheet. */
    private fun tapChip(name: String) {
        // The section is last in the editor: on a tall pane it can sit below the fold.
        rule.onNode(hasText(name) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Selected)).performScrollTo().performClick()
        rule.waitForIdle()
    }

    /** A list row by its title, never the search field holding the same text. */
    private fun rowText(text: String) = rule.onNode(hasText(text) and !hasSetTextAction())

    private fun bulkAction(label: Int) {
        rule.onNode(hasText(string(label)) and hasClickAction() and hasAnyAncestor(hasTestTag(BULK_ACTION_BAR_TAG))).performClick()
        rule.waitForIdle()
    }

    private fun typeTravelName(name: String) {
        rule.waitUntil(20_000) { rule.onAllNodes(hasSetTextAction() and hasText(string(R.string.travel_name))).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(hasSetTextAction() and hasText(string(R.string.travel_name))).performTextReplacement(name)
        rule.onNode(hasText(string(R.string.save)) and hasClickAction()).performClick()
        rule.waitForIdle()
    }

    private val signedTotal get() = formatSignedCurrency(BigDecimal("-230.00"), "EUR")

    @Test
    fun ac01_activityGroupsTheTrip_compact() {
        host()
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(travelRow("Barcellona")).assert(hasText(plural(R.plurals.travel_expenses, 3), substring = true))
        rule.onNode(travelRow("Barcellona")).assert(hasText(signedTotal))
        rule.onAllNodes(hasText("Montagna", substring = true)).assertCountEquals(0)
        rule.onAllNodes(hasText("Hotel")).assertCountEquals(0)
        // Totals still count each underlying expense once.
        rule.onNodeWithText(formatSignedCurrency(BigDecimal("50.00"), "EUR"), substring = true).assertExists()

        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("taxi")
        awaitText("Taxi")
        rule.onAllNodes(travelRow("Barcellona")).assertCountEquals(0)
        rule.onNode(hasText("Taxi") and hasContentDescription(string(R.string.in_travel, "Barcellona"), substring = true)).assertExists()
    }

    @Test
    fun ac02_detailStatsAndAddExpense_compact() {
        host()
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(travelRow("Barcellona")).performClick()
        awaitText(string(R.string.travel_per_day))
        listOf(
            signedTotal,
            plural(R.plurals.travel_days, 5),
            formatCurrency(BigDecimal("56.00"), "EUR"),
            string(R.string.travel_refunded),
            string(R.string.travel_where_it_went),
        ).forEach { rule.onNode(hasText(it, substring = true)).assertExists() }
        val travelBar = rule.onAllNodes(hasText("Travel")).onFirst().fetchSemanticsNode().boundsInRoot.top
        val taxiBar = rule.onAllNodes(hasText("Taxi & Rideshare")).onFirst().fetchSemanticsNode().boundsInRoot.top
        assertTrue("biggest spend first", travelBar < taxiBar)

        rule.onNode(hasText(string(R.string.travel_add_expense)) and hasClickAction()).performScrollTo().performClick()
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Barcellona") and isSelected()).fetchSemanticsNodes().isNotEmpty() }
        rule.onAllNodes(hasSetTextAction())[0].performTextInput("10")
        rule.onNode(hasContentDescription(string(R.string.add_transaction)) and hasClickAction()).performClick()
        awaitStored { s -> s.values.count { it.travelId == barcellona } == 4 }
    }

    @Test
    fun ac03_manageTravels_compact() {
        host()
        // A long press enters selection with the trip expanded, and does not open the detail.
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(travelRow("Barcellona")).performTouchInput { longClick() }
        rule.waitUntil(20_000) { rule.onAllNodes(isToggleable() and hasText("Hotel", substring = true)).fetchSemanticsNodes().isNotEmpty() }
        rule.onAllNodes(hasText(string(R.string.travel_per_day))).assertCountEquals(0)
        Espresso.pressBack()
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }

        tapDescribed(R.string.travels_title)
        awaitText("Montagna", substring = true)
        rule.onNode(travelRow("Barcellona")).assertExists()

        tapDescribed(R.string.add_travel)
        typeTravelName("Lisbona")
        rule.waitUntil(20_000) { "Lisbona" in travelNames() }

        rule.onNode(travelRow("Lisbona")).performClick()
        tapDescribed(R.string.travel_options)
        tapText(string(R.string.rename))
        typeTravelName("Lisboa")
        rule.waitUntil(20_000) { "Lisboa" in travelNames() }
        Espresso.pressBack()

        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(travelRow("Barcellona")).performTouchInput { swipeLeft() }
        awaitText(string(R.string.delete_travel_title, "Barcellona"))
        tapText(string(R.string.cancel))
        assertTrue("cancel keeps it", "Barcellona" in travelNames())

        rule.onNode(travelRow("Barcellona")).performTouchInput { swipeLeft() }
        awaitText(string(R.string.delete_travel_title, "Barcellona"))
        tapText(string(R.string.delete_travel))
        rule.waitUntil(20_000) { "Barcellona" !in travelNames() }
        val after = stored()
        assertEquals(5, after.size)
        assertEquals(listOf(null, null, null), listOf("Hotel", "Taxi", "Rimborso").map { after.getValue(it).travelId })

        // Deleting from a travel's page lands back on the list, once (code review r1).
        rule.onNode(travelRow("Lisboa")).performClick()
        awaitText(string(R.string.travel_add_expense))
        tapDescribed(R.string.travel_options)
        tapText(string(R.string.delete_travel))
        awaitText(string(R.string.delete_travel_title, "Lisboa"))
        rule.onAllNodes(tappable(string(R.string.delete_travel))).onFirst().performClick()
        rule.waitUntil(20_000) { "Lisboa" !in travelNames() }
        awaitText("Montagna", substring = true)
        rule.onNode(hasContentDescription(string(R.string.add_travel)) and hasClickAction()).assertExists()
    }

    @Test
    fun ac04_assignFromTheForm_compact() {
        host()
        rowText("Caffè").performScrollTo().performClick()
        awaitText(string(R.string.part_of_a_trip))
        tapChip("Barcellona")
        tapDescribed(R.string.save)
        awaitStored { it.getValue("Caffè").travelId == barcellona }

        // Back in the plain list Caffè now belongs to the trip; search to reach it again.
        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("caff")
        awaitText("Caffè")
        rowText("Caffè").performScrollTo().performClick()
        awaitText(string(R.string.part_of_a_trip))
        tapChip(string(R.string.travel_none))
        tapDescribed(R.string.save)
        awaitStored { it.getValue("Caffè").travelId == null }

        // Create and select from the form's +.
        rowText("Caffè").performScrollTo().performClick()
        awaitText(string(R.string.part_of_a_trip))
        tapDescribed(R.string.add_travel)
        typeTravelName("Lisbona")
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Lisbona") and isSelected()).fetchSemanticsNodes().isNotEmpty() }
        tapDescribed(R.string.save)
        awaitStored { s -> s.getValue("Caffè").travelId != null && s.getValue("Caffè").travelId != barcellona }

        // A goal transfer is never a trip expense: no travel section.
        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("Risparmio")
        awaitText("Risparmio")
        rowText("Risparmio").performClick()
        rule.waitForIdle()
        rule.onAllNodes(hasText(string(R.string.part_of_a_trip))).assertCountEquals(0)
    }

    @Test
    fun ac04_assignFromTheSelection_compact() {
        host()
        rowText("Caffè").performScrollTo().performTouchInput { longClick() }
        awaitText(plural(R.plurals.selection_count, 1))
        bulkAction(R.string.bulk_travel)
        awaitText(string(R.string.move_to_travel))
        rule.onAllNodes(hasText(string(R.string.remove_from_travel))).assertCountEquals(0)
        rule.onNode(travelRow("Barcellona")).performClick()
        awaitStored { it.getValue("Caffè").travelId == barcellona }
        awaitGone(hasText(string(R.string.move_to_travel)))

        // Taxi is tagged: Remove is offered and untags it.
        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("Taxi")
        awaitText("Taxi")
        rowText("Taxi").performTouchInput { longClick() }
        awaitText(plural(R.plurals.selection_count, 1))
        bulkAction(R.string.bulk_travel)
        tapText(string(R.string.remove_from_travel))
        awaitStored { it.getValue("Taxi").travelId == null }

        // From the detail: a long press on a member offers Remove from travel.
        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("")
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(travelRow("Barcellona")).performClick()
        awaitText("Hotel")
        rule.onNode(hasText("Hotel") and hasClickAction()).performScrollTo().performTouchInput { longClick() }
        tapText(string(R.string.remove_from_travel))
        awaitStored { it.getValue("Hotel").travelId == null }
    }

    @Test
    fun ac04_createFromAnEmptyMoveSheet_compact() {
        runBlocking { app.travelRepository.observeAll().first().forEach { app.travelRepository.delete(it.id) } }
        host()
        rowText("Caffè").performScrollTo().performTouchInput { longClick() }
        awaitText(plural(R.plurals.selection_count, 1))
        bulkAction(R.string.bulk_travel)
        awaitText(string(R.string.no_travels_title))
        tapText(string(R.string.add_travel))
        typeTravelName("Roma")
        rule.waitUntil(20_000) { "Roma" in travelNames() }
        val roma = runBlocking { app.travelRepository.observeAll().first() }.single().id
        awaitStored { it.getValue("Caffè").travelId == roma }
    }

    /** R2': a Travel move drops a showing bulk Undo at once, so it can never put the old rows back. */
    @Test
    fun ac04_aMoveDropsAPendingBulkUndo_compact() = withUndoWindowOf(seconds = 15) {
        host()
        rowText("Caffè").performScrollTo().performTouchInput { longClick() }
        awaitText(plural(R.plurals.selection_count, 1))
        bulkAction(R.string.bulk_amount)
        rule.waitUntil(20_000) { rule.onAllNodes(hasTestTag(BULK_INPUT_TAG)).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag(BULK_INPUT_TAG).performTextReplacement("4")
        rule.onNode(hasText(string(R.string.bulk_set)) and hasClickAction()).performClick()
        awaitText(plural(R.plurals.transactions_updated, 1))

        rowText("Caffè").performScrollTo().performTouchInput { longClick() }
        bulkAction(R.string.bulk_travel)
        // Still showing right before the move, or the drop below proves nothing.
        rule.onNode(hasText(plural(R.plurals.transactions_updated, 1))).assertExists()
        rule.onNode(travelRow("Barcellona")).performClick()
        // Gone at once: well inside its own 5 s window.
        rule.waitUntil(2_000) { rule.onAllNodes(hasText(plural(R.plurals.transactions_updated, 1))).fetchSemanticsNodes().isEmpty() }
        awaitStored { it.getValue("Caffè").travelId == barcellona }
        assertEquals(0, BigDecimal("-4").compareTo(stored().getValue("Caffè").amount))
    }

    @Test
    fun ac05_semantics_compact() {
        host()
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        val description = rule.onNode(travelRow("Barcellona")).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(description, description.startsWith("Barcellona, ${plural(R.plurals.travel_expenses, 3)}"))
        rule.onNode(travelRow("Barcellona")).performClick()
        awaitText(string(R.string.travel_where_it_went))
        rule.onNode(hasText("Travel") and SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "89%")).assertExists()
        rule.onNode(hasText("Taxi & Rideshare") and SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "11%")).assertExists()
    }

    @Test
    fun ac05_wideGroupsAndAssignsToo() {
        host(widthDp = 900)
        rule.waitUntil(20_000) { rule.onAllNodes(travelRow("Barcellona")).fetchSemanticsNodes().isNotEmpty() }
        rowText("Caffè").performScrollTo().performClick()
        awaitText(string(R.string.part_of_a_trip))
        tapChip("Barcellona")
        tapDescribed(R.string.save)
        awaitStored { it.getValue("Caffè").travelId == barcellona }
        rule.onNode(travelRow("Barcellona")).performClick()
        awaitText(string(R.string.travel_per_day))
    }

    @Test
    fun ac06_singleDeleteUndoKeepsTheTag_compact() {
        host()
        rule.onNodeWithTag(ACTIVITY_SEARCH_TAG).performTextReplacement("Taxi")
        awaitText("Taxi")
        rowText("Taxi").performTouchInput { swipeLeft() }
        tapText(string(R.string.delete_transaction))
        awaitStored { "Taxi" !in it }
        rule.onNode(hasText(string(R.string.undo)) and hasClickAction()).performClick()
        awaitStored { it["Taxi"]?.travelId == barcellona }
        assertNull(stored().getValue("Caffè").travelId)
    }
}

/** Fixture T of #284 on a clean store; shared with `TravelsCaptureTest`. Returns Barcellona's id. */
internal suspend fun seedTravelFixture(app: PersonalFinanceApplication): String {
    app.database.clearAllTables()
    app.categoryRepository.seedDefaultsIfEmpty()
    val categories = app.categoryRepository.observeAll().first()
    fun cat(name: String, type: TransactionType) = categories.first { it.name == name && it.type == type }
    val goal = app.goalRepository.add(NewGoal(name = "Holiday", targetAmount = BigDecimal("500"))).id
    app.travelRepository.add("Montagna", "mountain.2")
    val trip = app.travelRepository.add("Barcellona", "airplane")
    fun row(id: String, date: String, amount: String, category: String, type: TransactionType, travel: String? = null, goalId: String? = null) =
        cat(category, type).let { c ->
            FinanceTransaction(
                id = id, timestamp = Instant.parse("2026-09-${date}T10:00:00Z"), amount = BigDecimal(amount), note = id,
                categoryLabel = c.name, categoryId = c.id, currencyCode = "EUR", goalId = goalId, recurrenceRuleId = null, travelId = travel,
            )
        }
    app.transactionRepository.upsertAll(
        listOf(
            row("Hotel", "12", "-250.00", "Travel", TransactionType.EXPENSE, trip.id),
            row("Taxi", "14", "-30.00", "Taxi & Rideshare", TransactionType.EXPENSE, trip.id),
            row("Rimborso", "16", "50.00", "Refund", TransactionType.INCOME, trip.id),
            row("Caffè", "15", "-3.00", "Coffee & Drinks", TransactionType.EXPENSE),
            row("Risparmio", "11", "-20.00", "Other", TransactionType.EXPENSE, goalId = goal),
        ),
    )
    return trip.id
}
