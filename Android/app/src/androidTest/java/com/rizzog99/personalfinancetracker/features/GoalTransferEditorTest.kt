package com.rizzog99.personalfinancetracker.features

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.travel.FinanceTravel
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.features.travels.TravelChoice
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #300 AC-01/AC-02 on the editor itself: Transfer type, goal picker, interval limits, and editing an
 * existing transfer. Goals come from the app's real store, as in production.
 */
@RunWith(AndroidJUnit4::class)
class GoalTransferEditorTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private fun string(id: Int) = app.getString(id)
    private lateinit var categories: List<FinanceCategory>
    private lateinit var emergencyFund: FinanceGoal
    private lateinit var holiday: FinanceGoal

    @Before
    fun setUp() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        categories = app.categoryRepository.observeAll().first()
    }

    private fun seedGoals() = runBlocking {
        emergencyFund = app.goalRepository.add(NewGoal("Emergency fund", BigDecimal("5000")))
        holiday = app.goalRepository.add(NewGoal("Holiday", BigDecimal("1500")))
    }

    private var saved: Pair<FinanceTransaction, NewRecurrenceRule?>? = null

    private fun show(editing: FinanceTransaction? = null, presetRepeats: Boolean = false, travelChoice: TravelChoice? = null) {
        rule.setContent {
            PersonalFinanceTheme {
                TransactionEditorSheet(
                    editingTransaction = editing,
                    categories = categories,
                    receiptMappingRepository = app.receiptMappingRepository,
                    onDismiss = {},
                    onSave = { transaction, newRule, _ -> saved = transaction to newRule },
                    presetRepeats = presetRepeats,
                    travelChoice = travelChoice,
                )
            }
        }
        rule.waitForIdle()
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    private val transferOption get() = hasText(string(R.string.transaction_type_transfer)) and hasClickAction()
    private fun goalTile(name: String) = hasText(name) and hasClickAction()
    private val increase get() = hasContentDescription(string(R.string.increase_interval)) and hasClickAction()
    private val decrease get() = hasContentDescription(string(R.string.decrease_interval)) and hasClickAction()
    private fun frequency(id: Int) = hasText(string(id)) and hasClickAction()
    private fun intervalShows(value: String) = rule.onNode(hasText(value)).assertExists()
    private fun tap(matcher: SemanticsMatcher, times: Int = 1) = repeat(times) { rule.onNode(matcher).performScrollTo().performClick() }
    /** Top-bar buttons: nothing to scroll. */
    private fun press(matcher: SemanticsMatcher) = rule.onNode(matcher).performClick()

    private fun transfer(amount: String, goal: FinanceGoal) = FinanceTransaction(
        id = "transfer-1",
        timestamp = Instant.parse("2026-01-27T09:00:00Z"),
        amount = BigDecimal(amount),
        note = "",
        categoryLabel = "→ ${goal.name}",
        categoryId = null,
        currencyCode = "EUR",
        goalId = goal.id,
        recurrenceRuleId = null,
    )

    @Test
    fun ac01_newTransferNeedsAGoalAndKeepsItOnTheRule() {
        seedGoals()
        show(presetRepeats = true)
        waitFor(transferOption)
        rule.onAllNodes(hasSetTextAction())[0].performTextReplacement("200")

        tap(transferOption)
        rule.onNode(hasContentDescription(string(R.string.add_transaction)) and hasClickAction()).assertIsNotEnabled()
        waitFor(goalTile("Emergency fund"))
        tap(goalTile("Emergency fund"))
        rule.onNode(goalTile("Emergency fund")).assertIsSelected()
        tap(frequency(R.string.recurrence_monthly))
        tap(increase)
        intervalShows("2")
        rule.onNode(hasContentDescription(string(R.string.add_transaction)) and hasClickAction()).assertIsEnabled().performClick()

        val (transaction, newRule) = requireNotNull(saved)
        assertEquals(0, BigDecimal("-200").compareTo(transaction.amount))
        assertEquals(emergencyFund.id, transaction.goalId)
        assertNull(transaction.categoryId)
        assertEquals("→ Emergency fund", transaction.categoryLabel)
        assertEquals(RecurrenceFrequency.MONTHLY to 2, newRule?.frequency to newRule?.interval)
        assertEquals(emergencyFund.id, newRule?.goalId)
        assertNull(newRule?.categoryId)
    }

    @Test
    fun ac01_transferIsOfferedOnlyWithGoals() {
        show()
        waitFor(hasText(string(R.string.filter_expense)) and hasClickAction())
        rule.onNode(transferOption).assertDoesNotExist()

        seedGoals()
        waitFor(transferOption)
    }

    @Test
    fun ac01_intervalCapsAndClamps() {
        show(presetRepeats = true)
        tap(frequency(R.string.recurrence_weekly))
        tap(increase, times = 60)
        intervalShows("52")
        rule.onNode(increase).assertIsNotEnabled()
        tap(decrease, times = 22)
        intervalShows("30")
        tap(frequency(R.string.recurrence_monthly))
        intervalShows("24")
        rule.onNode(increase).assertIsNotEnabled()
        tap(frequency(R.string.recurrence_yearly))
        intervalShows("10")
    }

    @Test
    fun ac01_retapTransferKeepsTheGoalAndHidesTravel() {
        seedGoals()
        val trip = FinanceTravel("trip", "Barcellona", "airplane", Instant.EPOCH)
        show(travelChoice = TravelChoice(listOf(trip), onCreate = { _, _ -> null }))
        waitFor(transferOption)
        rule.onAllNodes(hasText(string(R.string.part_of_a_trip))).fetchSemanticsNodes().let {
            check(it.isNotEmpty()) { "precondition: the travel section shows for an expense" }
        }

        tap(transferOption)
        tap(goalTile("Holiday"))
        tap(transferOption)

        rule.onNode(goalTile("Holiday")).assertIsSelected()
        rule.onAllNodes(hasText(string(R.string.part_of_a_trip))).fetchSemanticsNodes().let {
            assertEquals("travel section hidden on Transfer", 0, it.size)
        }
    }

    @Test
    fun ac02_editTransferUnchangedKeepsTheLink() {
        seedGoals()
        val original = transfer("-50.00", emergencyFund)
        show(editing = original)
        // Save as soon as it is possible: before #300 that was at once, and it rewrote the row as an expense.
        val save = hasContentDescription(string(R.string.save)) and hasClickAction()
        waitFor(save and isEnabled())

        press(save)

        val edited = requireNotNull(saved?.first)
        assertEquals(original.copy(amount = edited.amount), edited)
        assertEquals(0, original.amount.compareTo(edited.amount))
    }

    @Test
    fun ac02_editTransferToAnotherGoalRelabels() {
        seedGoals()
        show(editing = transfer("-50.00", emergencyFund))
        waitFor(goalTile("Holiday"))

        rule.onAllNodes(hasSetTextAction())[0].performTextReplacement("80")
        tap(goalTile("Holiday"))
        press(hasContentDescription(string(R.string.save)) and hasClickAction())

        val edited = requireNotNull(saved?.first)
        assertEquals(0, BigDecimal("-80").compareTo(edited.amount))
        assertEquals(holiday.id, edited.goalId)
        assertEquals("→ Holiday", edited.categoryLabel)
        assertNull(edited.categoryId)
    }
}
