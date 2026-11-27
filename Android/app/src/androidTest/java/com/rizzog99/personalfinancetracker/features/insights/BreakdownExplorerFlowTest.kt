package com.rizzog99.personalfinancetracker.features.insights

import android.text.format.DateUtils
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasAnyDescendant
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
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.formatters.formatTransactionDate
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Formatter
import java.util.Locale
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
 * #303 AC-01..04, 06, 09 on the app's real store through the production `InsightsScreen`, with the
 * clock pinned to fixture F: 10 Sep 2026 12:00, Europe/Rome, en-US formatting.
 */
@RunWith(AndroidJUnit4::class)
class BreakdownExplorerFlowTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private fun string(id: Int, vararg args: Any) = app.getString(id, *args)
    private val zone = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(at(2026, 9, 10), zone)
    private val previousLocale = Locale.getDefault()

    private fun at(y: Int, m: Int, d: Int): Instant = LocalDateTime.of(y, m, d, 12, 0).atZone(zone).toInstant()

    @Before
    fun setUp(): Unit = runBlocking {
        Locale.setDefault(Locale.US)
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        val holiday = app.goalRepository.add(NewGoal("Holiday", BigDecimal("1500")))
        // Food rows are linked to a real category, as every row the editor saves is: editing one
        // keeps it in Food instead of moving it to the editor's default category.
        val food = app.categoryRepository.add(
            com.rizzog99.personalfinancetracker.domain.category.NewCategory(
                "Food", "fork.knife", com.rizzog99.personalfinancetracker.domain.category.TransactionType.EXPENSE,
            ),
        )
        fun tx(id: String, amount: String, label: String, day: Instant, goalId: String? = null) =
            FinanceTransaction(id, day, BigDecimal(amount), "", label, food.id.takeIf { label == "Food" }, "EUR", goalId, null)
        listOf(
            tx("f1", "-100", "Food", at(2026, 8, 5)),
            tx("f2", "-200", "Food", at(2026, 8, 20)),
            tx("s", "2000", "Salary", at(2026, 9, 1)),
            tx("f3", "-60", "Food", at(2026, 9, 3)),
            tx("fun", "-50", "Fun", at(2026, 9, 5)),
            tx("t", "-500", "→ Holiday", at(2026, 9, 6), goalId = holiday.id),
            tx("f4", "-90", "Food", at(2026, 9, 8)),
            tx("r", "-800", "Rent", at(2026, 9, 25)),
        ).forEach { app.transactionRepository.upsert(it) }
        app.transactionRepository.observeAll().first { it.size == 8 }
    }

    @After
    fun restoreLocale() = Locale.setDefault(previousLocale)

    private fun host() {
        rule.setContent {
            PersonalFinanceTheme {
                InsightsScreen(isDarkTheme = false, onToggleTheme = {}, onOpenSettings = {}, clock = clock)
            }
        }
        waitFor(hasText("Sep 2026"))
    }

    private fun waitFor(matcher: SemanticsMatcher) = waitUntil { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    /** On timeout, logs every text on screen (tag `EXPLORER`) so the failure says what was there instead. */
    private fun waitUntil(condition: () -> Boolean) = runCatching { rule.waitUntil(20_000, condition) }.onFailure {
        rule.onAllNodes(SemanticsMatcher("any") { true }, useUnmergedTree = true).fetchSemanticsNodes(atLeastOneRootRequired = false)
            .mapNotNull { node ->
                (node.config.getOrNull(SemanticsProperties.Text)?.joinToString() ?: "") + " | " +
                    (node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString() ?: "")
            }
            .filter { it != " | " }
            .forEach { android.util.Log.e("EXPLORER", it) }
        com.rizzog99.personalfinancetracker.ui.CaptureHarness.writeScreenPng(
            com.rizzog99.personalfinancetracker.ui.CaptureHarness.outputDir("explorer-debug"),
            "timeout-${System.currentTimeMillis()}",
        )
        throw it
    }.getOrThrow()

    private fun row(name: String) = hasContentDescription(name) and hasClickAction()
    private fun rowState(name: String): String =
        rule.onNode(row(name)).fetchSemanticsNode().config[SemanticsProperties.StateDescription]
    private val previous get() = hasContentDescription(string(R.string.explorer_previous))
    private val next get() = hasContentDescription(string(R.string.explorer_next))

    @Test
    fun ac01_septemberExpenses() {
        host()
        rule.onNode(hasText("€1,000.00")).assertExists()
        assertEquals("€800.00, 80.0% of total, about the same as previous period", rowState("Rent"))
        assertEquals("€150.00, 15.0% of total, up 50% from previous period", rowState("Food"))
        assertEquals("€50.00, 5.0% of total, new", rowState("Fun"))
        // The goal transfer is in no row, slice or bar.
        assertTrue(
            rule.onAllNodes(hasText("Holiday", substring = true) or hasContentDescription("Holiday", substring = true))
                .fetchSemanticsNodes().isEmpty(),
        )
        rule.onNode(next).assertIsNotEnabled()
        rule.onNode(previous).assertIsEnabled()
    }

    @Test
    fun ac02_incomeAndEmptyPeriod() {
        host()
        rule.onNode(hasText(string(R.string.explorer_income)) and hasClickAction()).performClick()
        val salary = string(R.string.builtin_category_salary)
        waitFor(row(salary))
        assertEquals("€2,000.00, 100.0% of total, new", rowState(salary))
        rule.onNode(previous).performClick()
        waitFor(hasText(string(R.string.explorer_empty_income, "Aug 2026")))
        rule.onNode(hasText(string(R.string.explorer_empty_hint))).assertExists()
    }

    @Test
    fun ac03_navigation() {
        host()
        rule.onNode(previous).performClick()
        waitFor(hasText("Aug 2026"))
        rule.onNode(previous).assertIsNotEnabled()
        assertEquals("€300.00, 100.0% of total, new", rowState("Food"))
        rule.onNode(hasText("Aug 2026") and hasClickAction()).performClick()
        rule.onNode(hasText(string(R.string.explorer_year))).performClick()
        waitFor(hasText("2026"))
        rule.onNode(hasText("Aug 2026")).assertDoesNotExist()
    }

    @Test
    fun ac04_customRangeCancelAndApply() {
        host()
        rule.onNode(hasText("Sep 2026") and hasClickAction()).performClick()
        rule.onNode(hasText(string(R.string.explorer_custom_range_menu))).performClick()
        waitFor(hasText(string(R.string.explorer_custom_range)))
        rule.onNode(hasText(string(R.string.cancel)) and hasClickAction()).performClick()
        waitUntil { rule.onAllNodes(hasText(string(R.string.explorer_custom_range))).fetchSemanticsNodes().isEmpty() }
        rule.onNode(hasText("Sep 2026")).assertExists()

        // Apply with the picker's default selection: the viewed month clamped to today, 1–10 Sep.
        rule.onNode(hasText("Sep 2026") and hasClickAction()).performClick()
        rule.onNode(hasText(string(R.string.explorer_custom_range_menu))).performClick()
        waitFor(hasText(string(R.string.explorer_apply)))
        rule.onNode(hasText(string(R.string.explorer_apply)) and hasClickAction()).performClick()
        val start = LocalDate.of(2026, 9, 1).atStartOfDay(zone).toInstant().toEpochMilli()
        val end = LocalDate.of(2026, 9, 11).atStartOfDay(zone).toInstant().toEpochMilli() - 1
        val expected = DateUtils.formatDateRange(
            app, Formatter(StringBuilder(), Locale.US), start, end,
            DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_SHOW_YEAR or DateUtils.FORMAT_ABBREV_MONTH, zone.id,
        ).toString()
        runCatching { waitFor(hasText(expected)) }.onFailure {
            rule.onAllNodes(hasClickAction()).fetchSemanticsNodes().forEach { node ->
                android.util.Log.e("AC04", "${node.config.getOrNull(SemanticsProperties.Text)} ${node.config.getOrNull(SemanticsProperties.ContentDescription)}")
            }
            android.util.Log.e("AC04", "expected=$expected")
            throw it
        }
        // Rent (25 Sep) is outside 1–10 Sep.
        rule.onNode(row("Rent")).assertDoesNotExist()
        // Compared with 22–31 Aug, where Food has nothing: new.
        assertEquals("€150.00, 75.0% of total, new", rowState("Food"))
    }

    @Test
    fun ac06_drillDownAndEdit() {
        host()
        rule.onNode(row("Food")).performScrollTo().performClick()
        waitFor(hasText(string(R.string.explorer_drill_summary, string(R.string.explorer_expenses), "Sep 2026")))
        rule.onNode(hasText("€150.00")).assertExists()
        rule.onNode(hasText(app.resources.getQuantityString(R.plurals.explorer_transactions, 2, 2))).assertExists()
        val sep8 = rule.onNode(hasText(formatTransactionDate(at(2026, 9, 8))) and isHeading()).fetchSemanticsNode().boundsInRoot.top
        val sep3 = rule.onNode(hasText(formatTransactionDate(at(2026, 9, 3))) and isHeading()).fetchSemanticsNode().boundsInRoot.top
        assertTrue("newest day first", sep8 < sep3)

        rule.onNode(hasClickAction() and hasAnyDescendant(hasText("90", substring = true)), useUnmergedTree = true).performClick()
        waitFor(hasSetTextAction())
        rule.onAllNodes(hasSetTextAction())[0].performTextReplacement("40")
        rule.onNode(hasContentDescription(string(R.string.save)) and hasClickAction()).performClick()
        waitFor(hasText("€100.00"))
        waitUntil { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().isEmpty() }

        rule.onNode(hasContentDescription(string(R.string.back)) and hasClickAction()).performClick()
        waitFor(row("Food"))
        assertTrue(rowState("Food").startsWith("€100.00, "))
    }

    @Test
    fun ac09_chartsAndControlsAreReadable() {
        host()
        val sep8 = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.US).format(LocalDate.of(2026, 9, 8))
        rule.onNode(hasContentDescription("$sep8, €90.00")).assertExists()
        rule.onNode(hasContentDescription("Food, 15.0%")).assertExists()
        rule.onNode(hasText(string(R.string.explorer_breakdown)) and isHeading()).assertExists()
        rule.onNode(previous and hasClickAction()).assertExists()
        rule.onNode(next and hasClickAction()).assertExists()
        // The period button tells TalkBack what it changes.
        val label = rule.onNode(hasText("Sep 2026") and hasClickAction()).fetchSemanticsNode()
            .config[androidx.compose.ui.semantics.SemanticsActions.OnClick].label
        assertEquals(string(R.string.explorer_period_hint), label)
    }
}
