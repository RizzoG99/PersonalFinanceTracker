package com.rizzog99.personalfinancetracker.features

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import com.rizzog99.personalfinancetracker.features.home.SAFE_TO_SPEND_BREAKDOWN_TAG
import com.rizzog99.personalfinancetracker.features.home.SAFE_TO_SPEND_HERO_TAG
import com.rizzog99.personalfinancetracker.features.home.SAFE_TO_SPEND_WHAT_IF_TAG
import com.rizzog99.personalfinancetracker.ui.formatters.formatWholeCurrency
import java.math.RoundingMode
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatDayMonth
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #298 on the real store through the production Home and Settings. Amounts are fixed; dates are
 * relative to the device's today (D-04) — exact cycle and rounding rules live in the JVM
 * `SafeToSpendCalculatorTest`.
 */
@RunWith(AndroidJUnit4::class)
class SafeToSpendFlowTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private fun string(id: Int, vararg args: Any) = app.getString(id, *args)

    @Before
    fun setUp() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        app.preferencesRepository.setPayCycleStartDay(1)
        app.preferencesRepository.setSafeToSpendBufferPercent(5)
        app.preferencesRepository.setHideBalance(false)
        app.preferencesRepository.setBaseCurrency("EUR")
    }

    private fun waitFor(condition: () -> Boolean) = rule.waitUntil(20_000, condition)
    private fun exists(matcher: SemanticsMatcher) = rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
    private fun tap(matcher: SemanticsMatcher) = rule.onNode(matcher).performScrollTo().performClick()
    private fun euro(amount: String) = formatCurrency(BigDecimal(amount), "EUR")
    private val title get() = hasText(string(R.string.safe_to_spend)) and isHeading()

    private var ids = 0

    private fun add(amount: String, at: Instant = Instant.now()) = runBlocking {
        app.transactionRepository.upsert(
            FinanceTransaction(
                id = "sts-${ids++}", timestamp = at, amount = BigDecimal(amount), note = "", categoryLabel = "Other",
                categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
            ),
        )
    }

    /** The day before payday is the cycle's last day. */
    private fun lastDay(): String = formatDayMonth(PayCycleService.financialMonthContaining(LocalDate.now(), 1).endInclusive)

    private fun hostHome(widthDp: Int = 411) {
        rule.setContent {
            val configuration = Configuration(LocalContext.current.resources.configuration).apply { screenWidthDp = widthDp }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) { PersonalFinanceNavHost() }
            }
        }
        waitFor { exists(title) }
    }

    private fun heroAndBreakdown(widthDp: Int) {
        add("1000")
        add("-200")
        hostHome(widthDp)

        waitFor { exists(hero and hasText(euro("750"))) }
        assertEquals(true, exists(hero and hasText(perDayLine("750"))))
        assertFalse("Total balance is replaced", exists(hasText("Total balance")))
        assertFalse("the hero no longer sums history", exists(hasText(euro("800"))))
        // Income/expense tiles stay until #299 (D-07).
        assertEquals(true, exists(hasText(string(R.string.filter_income))))

        tap(hasText(string(R.string.safe_to_spend_how)) and hasClickAction())
        waitFor { exists(inBreakdown(string(R.string.safe_to_spend_still_available))) }
        assertEquals(true, exists(inBreakdown(string(R.string.safe_to_spend_still_available)) and hasText(euro("800"))))
        assertEquals(
            true,
            exists(inBreakdown(string(R.string.safe_to_spend_buffer_row, 5)) and hasText(formatSignedCurrency(BigDecimal("-50"), "EUR"))),
        )
        assertEquals(true, exists(inBreakdown(string(R.string.safe_to_spend)) and hasText(euro("750"))))
        assertFalse("no rules: no recurring row", exists(inBreakdown(string(R.string.safe_to_spend_recurring_due))))
    }

    private val hero get() = hasTestTag(SAFE_TO_SPEND_HERO_TAG)
    private fun inBreakdown(label: String) = hasText(label) and hasAnyAncestor(hasTestTag(SAFE_TO_SPEND_BREAKDOWN_TAG))
    private fun inWhatIf() = hasAnyAncestor(hasTestTag(SAFE_TO_SPEND_WHAT_IF_TAG))

    /** "until <last day> · €N/day" for [amount] spread over the days left, today included, rounded down. */
    private fun perDayLine(amount: String, masked: Boolean = false): String {
        val cycle = PayCycleService.financialMonthContaining(LocalDate.now(), 1)
        val days = ChronoUnit.DAYS.between(LocalDate.now(), cycle.endInclusive.plusDays(1))
        val perDay = BigDecimal(amount).divide(BigDecimal(days), 0, RoundingMode.DOWN)
        return string(R.string.safe_to_spend_until_per_day, lastDay(), if (masked) "••••" else formatWholeCurrency(perDay, "EUR"))
    }

    @Test
    fun ac08_heroShowsSafeToSpendAndBreakdown() = heroAndBreakdown(411)

    /** Only meaningful on a really wide window (Pixel_Tablet / CI tablet job): skipped on phones. */
    @Test
    fun ac08_heroShowsSafeToSpendAndBreakdownWide() {
        val deviceWidth = app.resources.configuration.screenWidthDp
        assumeTrue("needs a wide device, this one is ${deviceWidth}dp", deviceWidth >= 900)
        heroAndBreakdown(deviceWidth)
    }

    @Test
    fun ac09_noIncomeButSpendingPointsAtThePayCycle() {
        add("-200")
        hostHome()
        val start = formatDayMonth(PayCycleService.financialMonthContaining(LocalDate.now(), 1).start)
        waitFor { exists(hasText(string(R.string.safe_to_spend_no_income_spent, start))) }
        // No figure in this state: income − spent would read −€200.00.
        assertFalse(exists(hasText(euro("-200"))))
    }

    @Test
    fun ac09_onlyOlderHistorySaysNoTransactionsSince() {
        add("500", at = Instant.now().minus(45, ChronoUnit.DAYS))
        hostHome()
        val start = formatDayMonth(PayCycleService.financialMonthContaining(LocalDate.now(), 1).start)
        waitFor { exists(hasText(string(R.string.safe_to_spend_no_income_history, start))) }
    }

    @Test
    fun ac09_emptyLedgerAsksForIncome() {
        hostHome()
        waitFor { exists(hasText(string(R.string.safe_to_spend_no_income_empty))) }
    }

    @Test
    fun ac07_usingBufferIsAmberLineNotOverPlan() {
        add("1000")
        add("-980")
        hostHome()
        waitFor { exists(hasText(euro("-30"))) }
        assertEquals(true, exists(hasText(string(R.string.safe_to_spend_using_buffer, lastDay()))))
        assertFalse(exists(hasText(string(R.string.safe_to_spend_over_plan, lastDay()))))
    }

    @Test
    fun ac07_pastTheBufferIsOverPlan() {
        add("1000")
        add("-1020")
        hostHome()
        waitFor { exists(hasText(euro("-70"))) }
        assertEquals(true, exists(hasText(string(R.string.safe_to_spend_over_plan, lastDay()))))
    }

    @Test
    fun ac10_bufferStepperChangesHome() {
        add("1000")
        add("-200")
        hostHome()
        waitFor { exists(hasText(euro("750"))) }

        rule.onNode(hasContentDescription(string(R.string.settings_title)) and hasClickAction()).performClick()
        val minus = hasContentDescription(string(R.string.decrease_safety_buffer))
        val plus = hasContentDescription(string(R.string.increase_safety_buffer))
        waitFor { exists(minus) }
        waitFor { exists(hasText(string(R.string.safety_buffer_value, 5))) }
        repeat(5) { tap(minus) }
        waitFor { exists(hasText(string(R.string.safety_buffer_value, 0))) }
        rule.onNode(minus).assertIsNotEnabled()
        repeat(20) { tap(plus) }
        waitFor { exists(hasText(string(R.string.safety_buffer_value, 20))) }
        rule.onNode(plus).assertIsNotEnabled()
        rule.onNode(minus).assertIsEnabled()
        waitFor { runBlocking { app.preferencesRepository.safeToSpendBufferPercent.first() } == 20 }

        rule.onNode(hasContentDescription(string(R.string.back)) and hasClickAction()).performClick()
        // 1000 − 200 − 20 % of 1000.
        waitFor { exists(hasText(euro("600"))) }
    }

    @Test
    fun ac11_whatIfShowsWhatASpendWouldLeaveAndSavesNothing() {
        add("1000")
        add("-200")
        hostHome()
        waitFor { exists(hasText(euro("750"))) }
        val before = runBlocking { app.transactionRepository.observeAll().first().size }

        tap(hasText(string(R.string.what_if_title)) and hasClickAction())
        waitFor { exists(hasSetTextAction()) }
        val outcome = inWhatIf() and hasText(lastDay(), substring = true)
        rule.waitForIdle()
        assertFalse("empty input shows nothing", exists(outcome))

        rule.onNode(hasSetTextAction()).performTextReplacement("100")
        waitFor { exists(outcome and hasText(euro("650"))) }
        assertEquals(true, exists(outcome and hasText(perDayLine("650"))))

        // Letters are dropped as typed (AmountInput.sanitize): nothing left to simulate.
        rule.onNode(hasSetTextAction()).performTextReplacement("abc")
        waitFor { !exists(outcome) }
        rule.onNode(hasSetTextAction()).performTextReplacement("0")
        rule.waitForIdle()
        assertFalse("zero is not a spend", exists(outcome))
        assertEquals(before, runBlocking { app.transactionRepository.observeAll().first().size })
    }

    @Test
    fun ac12_hideAmountsMasksEveryFigure() {
        add("1000")
        add("-200")
        hostHome()
        waitFor { exists(hasText(euro("750"))) }

        rule.onNode(hasContentDescription(string(R.string.hide_balance)) and hasClickAction()).performClick()
        waitFor { !exists(hasText(euro("750"))) }
        assertEquals(true, exists(hero and hasText(string(R.string.balance_hidden_placeholder))))
        assertEquals(true, exists(hero and hasText(perDayLine("750", masked = true))))
        assertFalse(exists(hasText(perDayLine("750"))))

        tap(hasText(string(R.string.safe_to_spend_how)) and hasClickAction())
        waitFor { exists(inBreakdown(string(R.string.safe_to_spend_still_available))) }
        assertEquals(true, exists(inBreakdown(string(R.string.safe_to_spend_still_available)) and hasText("••••")))
        assertFalse(exists(hasText(euro("800"))))
        assertFalse(exists(hasText(formatSignedCurrency(BigDecimal("-50"), "EUR"))))

        tap(hasText(string(R.string.what_if_title)) and hasClickAction())
        waitFor { exists(hasSetTextAction()) }
        rule.onNode(hasSetTextAction()).performTextReplacement("100")
        waitFor { exists(inWhatIf() and hasText(string(R.string.balance_hidden_placeholder))) }
        assertFalse(exists(hasText(euro("650"))))
        assertEquals(true, exists(title))
    }
}
