package com.rizzog99.personalfinancetracker.features

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasAnySibling
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isHeading
import com.rizzog99.personalfinancetracker.features.activity.ACTIVITY_SEARCH_TAG
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.recurring.RecurringRulesScreen
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** #300 AC-01/AC-02 end to end on the app's real store, through the production screens. */
@RunWith(AndroidJUnit4::class)
class GoalTransferFlowTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private fun string(id: Int) = app.getString(id)
    private val clock = Clock.fixed(Instant.parse("2026-11-21T11:00:00Z"), ZoneId.of("Europe/Rome"))
    private lateinit var emergencyFund: FinanceGoal
    private lateinit var holiday: FinanceGoal

    @Before
    fun setUp() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        emergencyFund = app.goalRepository.add(NewGoal("Emergency fund", BigDecimal("5000")))
        holiday = app.goalRepository.add(NewGoal("Holiday", BigDecimal("1500")))
    }

    @After
    fun restoreClock() {
        rule.mainClock.autoAdvance = true
    }

    private fun waitFor(condition: () -> Boolean) = rule.waitUntil(20_000, condition)
    private fun exists(matcher: SemanticsMatcher) = rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
    private fun tap(matcher: SemanticsMatcher) = rule.onNode(matcher).performScrollTo().performClick()
    /** Top-bar buttons: nothing to scroll. */
    private fun press(matcher: SemanticsMatcher) = rule.onNode(matcher).performClick()
    private val transferOption get() = hasText(string(R.string.transaction_type_transfer)) and hasClickAction()
    private fun goalTile(name: String) = hasText(name) and hasClickAction()
    private fun rules() = runBlocking { app.recurrenceRepository.observeAll().first() }
    private fun transactions() = runBlocking { app.transactionRepository.observeAll().first() }

    /** Amount 200, Transfer, Emergency fund, Month, every 2. Repeat must already be on. */
    private fun fillMonthlyTransferEvery2() {
        waitFor { exists(transferOption) }
        rule.onAllNodes(hasSetTextAction() and !hasTestTag(ACTIVITY_SEARCH_TAG))[0].performTextReplacement("200")
        tap(transferOption)
        waitFor { exists(goalTile("Emergency fund")) }
        tap(goalTile("Emergency fund"))
        tap(hasText(string(R.string.recurrence_monthly)) and hasClickAction())
        tap(hasContentDescription(string(R.string.increase_interval)) and hasClickAction())
    }

    private fun assertStoredMonthlyTransfer() {
        waitFor { rules().size == 1 && transactions().size == 1 }
        val stored = rules().single()
        assertEquals(RecurrenceFrequency.MONTHLY to 2, stored.frequency to stored.interval)
        assertEquals(0, BigDecimal("-200").compareTo(stored.amount))
        assertEquals(emergencyFund.id, stored.goalId)
        assertNull(stored.categoryId)
        assertEquals("→ Emergency fund", stored.categoryLabel)
        val occurrence = transactions().single()
        assertEquals(emergencyFund.id, occurrence.goalId)
        assertEquals(stored.id, occurrence.recurrenceRuleId)
        assertNull(occurrence.categoryId)
    }

    @Test
    fun ac01_recurringTransferFromRecurringRules() {
        rule.setContent { PersonalFinanceTheme { RecurringRulesScreen(onBack = {}, clock = clock) } }
        rule.onNode(hasContentDescription(string(R.string.recurring_add)) and hasClickAction()).performClick()

        fillMonthlyTransferEvery2()
        press(hasContentDescription(string(R.string.add_transaction)) and hasClickAction())

        assertStoredMonthlyTransfer()
    }

    @Test
    fun ac01_recurringTransferFromActivityAddWithRepeatToggle() {
        hostActivity()
        rule.onNode(hasContentDescription(string(R.string.add_transaction)) and hasClickAction()).performClick()
        val repeat = isToggleable() and hasAnySibling(hasText(string(R.string.repeat_transaction)))
        waitFor { exists(repeat) }
        tap(repeat)

        fillMonthlyTransferEvery2()
        // The sheet's Save, not the + behind it (same name): the one under the editor's heading.
        val editor = hasAnyDescendant(hasText(string(R.string.add_transaction)) and isHeading())
        press(hasContentDescription(string(R.string.add_transaction)) and hasClickAction() and hasAnyAncestor(editor))

        assertStoredMonthlyTransfer()
    }

    @Test
    fun ac02_ruleEditSwitchesTheGoal() {
        val goalRule: RecurrenceRule = runBlocking {
            app.recurrenceRepository.create(
                NewRecurrenceRule(
                    frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = Instant.parse("2026-12-01T09:00:00Z"),
                    amount = BigDecimal("-200.00"), note = "", categoryLabel = "→ Emergency fund", categoryId = null,
                    currencyCode = "EUR", goalId = emergencyFund.id,
                ),
            )
        }
        rule.setContent { PersonalFinanceTheme { RecurringRulesScreen(onBack = {}, editRuleId = goalRule.id, clock = clock) } }
        waitFor { exists(goalTile("Holiday")) }

        tap(goalTile("Holiday"))
        press(hasContentDescription(string(R.string.save)) and hasClickAction())

        waitFor { rules().single().goalId == holiday.id }
        val stored = rules().single()
        assertEquals("→ Holiday", stored.categoryLabel)
        assertNull(stored.categoryId)
        assertEquals(goalRule.startDate, stored.startDate)
    }

    @Test
    fun ac02_deleteThenUndoRestoresTheTransfer() {
        val original = FinanceTransaction(
            id = "ef-top-up", timestamp = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS), amount = BigDecimal("-50.00"), note = "EF top-up",
            categoryLabel = "→ Emergency fund", categoryId = null, currencyCode = "EUR",
            goalId = emergencyFund.id, recurrenceRuleId = null,
        )
        runBlocking { app.transactionRepository.upsert(original) }
        hostActivity()
        waitFor { exists(hasText("EF top-up")) }

        rule.onNodeWithText("EF top-up").performScrollTo().performTouchInput { swipeLeft() }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
        rule.onNodeWithText(string(R.string.delete_transaction)).performClick()
        val undo = hasText(string(R.string.undo)) and hasClickAction()
        val deadline = System.currentTimeMillis() + 60_000
        while (!(transactions().isEmpty() && exists(undo)) && System.currentTimeMillis() < deadline) {
            rule.mainClock.advanceTimeByFrame()
            Thread.sleep(16)
        }
        rule.mainClock.advanceTimeBy(500)
        rule.onNode(undo).performClick()
        rule.mainClock.autoAdvance = true

        waitFor { transactions().isNotEmpty() }
        val restored = transactions().single()
        assertEquals(original.copy(amount = restored.amount), restored)
        assertEquals(0, original.amount.compareTo(restored.amount))
    }

    private fun hostActivity() {
        rule.setContent {
            val configuration = Configuration(LocalContext.current.resources.configuration).apply { screenWidthDp = 411 }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) { PersonalFinanceNavHost() }
            }
        }
        rule.waitForIdle()
        with(NavShellMarkers()) { rule.selectTab(activityTab) }
    }
}
