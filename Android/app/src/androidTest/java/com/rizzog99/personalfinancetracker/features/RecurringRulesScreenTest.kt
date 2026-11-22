package com.rizzog99.personalfinancetracker.features

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasAnySibling
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.features.recurring.RecurringRulesScreen
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** #294 AC-02/03/04 end to end on the app's real store, through the production screen. */
@RunWith(AndroidJUnit4::class)
class RecurringRulesScreenTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private val zone = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(Instant.parse("2026-11-21T11:00:00Z"), zone)
    private lateinit var expenseCategoryId: String
    private lateinit var expenseCategoryName: String

    @Before
    fun setUp() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        val expense = app.categoryRepository.observeAll().first().first { it.type == TransactionType.EXPENSE }
        expenseCategoryId = expense.id
        expenseCategoryName = expense.name
    }

    private fun create(note: String, amount: String, start: String, autoRecord: Boolean = true): RecurrenceRule = runBlocking {
        app.recurrenceRepository.create(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY, interval = 1,
                startDate = LocalDate.parse(start).atTime(10, 0).atZone(zone).toInstant(),
                amount = BigDecimal(amount), note = note, categoryLabel = expenseCategoryName, categoryId = expenseCategoryId,
                currencyCode = "EUR", autoRecord = autoRecord,
            ),
        )
    }

    private fun show(editRuleId: String? = null) {
        rule.setContent { PersonalFinanceTheme { RecurringRulesScreen(onBack = {}, editRuleId = editRuleId, clock = clock) } }
    }

    private fun waitFor(timeoutMillis: Long = 20_000, condition: () -> Boolean) = rule.waitUntil(timeoutMillis, condition)

    private fun storedRule(id: String) = runBlocking { app.recurrenceRepository.observeAll().first().single { it.id == id } }

    @Test
    fun ac02_tapRuleOpensRuleEditorAndSavesTheTemplate() {
        val netflix = create("Netflix", "-12.99", "2026-12-01", autoRecord = false)
        assertTrue(runBlocking { app.transactionRepository.observeAll().first().isEmpty() })
        show()
        val tag = "recurringRule-${netflix.id}"
        waitFor { rule.onAllNodesWithTag(tag).fetchSemanticsNodes().size == 1 }

        rule.onNodeWithTag(tag).performClick()

        waitFor { rule.onAllNodes(hasText("Edit recurring")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Frequency: Monthly").assertExists()
        rule.onNodeWithText("Starts:", substring = true).assertExists()
        rule.onNodeWithText("Repeat transaction").assertDoesNotExist()
        rule.onNodeWithText("Date:", substring = true).assertDoesNotExist()
        rule.onAllNodes(hasSetTextAction())[0].performTextReplacement("15.99")
        rule.onAllNodes(hasSetTextAction())[1].performTextReplacement("Netflix 4K")
        rule.onNodeWithContentDescription("Save").performClick()

        waitFor { storedRule(netflix.id).note == "Netflix 4K" }
        val saved = storedRule(netflix.id)
        assertEquals(0, BigDecimal("-15.99").compareTo(saved.amount))
        assertEquals(netflix.startDate, saved.startDate)
        assertEquals(netflix.frequency to netflix.interval, saved.frequency to saved.interval)
        assertTrue(runBlocking { app.transactionRepository.observeAll().first().isEmpty() })
        waitFor { rule.onAllNodes(hasTestTag(tag) and hasText("15.99", substring = true)).fetchSemanticsNodes().size == 1 }
    }

    @Test
    fun ac02_editRuleIdOpensThatRulesEditor() {
        val rent = create("Rent", "-750.00", "2026-09-01")
        show(editRuleId = rent.id)

        waitFor { rule.onAllNodes(hasText("Edit recurring")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Frequency: Monthly").assertExists()
    }

    @Test
    fun ac03_swipeAndTalkBackStopTheRule() {
        val rent = create("Rent", "-750.00", "2026-09-01")
        val gym = create("Gym", "-30.00", "2026-09-10")
        show()
        val rentTag = "recurringRule-${rent.id}"
        val gymTag = "recurringRule-${gym.id}"
        waitFor { rule.onAllNodesWithTag(gymTag).fetchSemanticsNodes().size == 1 }
        assertNull(storedRule(rent.id).endDate)

        rule.onNodeWithTag(rentTag).performTouchInput { swipeLeft() }

        waitFor { rule.onAllNodesWithTag(rentTag).fetchSemanticsNodes().isEmpty() }
        waitFor { storedRule(rent.id).endDate != null }
        assertEquals(clock.instant(), storedRule(rent.id).endDate)

        // TalkBack's custom action on the other row.
        val stop = rule.onNodeWithTag(gymTag).fetchSemanticsNode().config[SemanticsActions.CustomActions].single { it.label == "Stop" }
        rule.runOnIdle { stop.action() }

        waitFor { rule.onAllNodesWithTag(gymTag).fetchSemanticsNodes().isEmpty() }
        waitFor { storedRule(gym.id).endDate != null }
        waitFor { rule.onAllNodes(hasText("No recurring transactions yet")).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test
    fun ac04_emptyStateAndAddOpensEditorWithRepeatOn() {
        show()
        waitFor { rule.onAllNodes(hasText("No recurring transactions yet")).fetchSemanticsNodes().isNotEmpty() }

        rule.onNodeWithContentDescription("Add recurring transaction").performClick()

        waitFor { rule.onAllNodes(isToggleable() and hasAnySibling(hasText("Repeat transaction"))).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(isToggleable() and hasAnySibling(hasText("Repeat transaction"))).assertIsOn()
    }
}
