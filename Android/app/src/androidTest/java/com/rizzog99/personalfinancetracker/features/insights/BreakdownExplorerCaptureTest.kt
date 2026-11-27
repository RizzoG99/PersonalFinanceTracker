package com.rizzog99.personalfinancetracker.features.insights

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #303 capture matrix on the production `InsightsScreen` and real store (fixture F plus a custom
 * "Climbing" category, AC-08): explorer top, category rows, drill-down and the empty Income state,
 * across EN/IT, light/dark and 100 %/200 % text. Width is the device's: run on `Pixel_7a` and again
 * on `Pixel_Tablet` for the wide cells.
 */
@RunWith(AndroidJUnit4::class)
class BreakdownExplorerCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private val zone = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(at(2026, 9, 10), zone)
    private val previousLocale = Locale.getDefault()
    private val outputDir: File get() = CaptureHarness.outputDir("breakdown-explorer-303")

    private fun at(y: Int, m: Int, d: Int): Instant = LocalDateTime.of(y, m, d, 12, 0).atZone(zone).toInstant()

    private val cells = listOf(
        CaptureHarness.Cell("en-light-100", locale = Locale.US),
        CaptureHarness.Cell("en-dark-100", locale = Locale.US, theme = ThemeMode.DARK),
        CaptureHarness.Cell("it-light-100", locale = Locale.ITALY),
        CaptureHarness.Cell("it-dark-100", locale = Locale.ITALY, theme = ThemeMode.DARK),
        CaptureHarness.Cell("en-light-200", locale = Locale.US, fontScale = 2f),
        CaptureHarness.Cell("it-dark-200", locale = Locale.ITALY, theme = ThemeMode.DARK, fontScale = 2f),
    )

    @Before
    fun seed(): Unit = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        val climbing = app.categoryRepository.add(NewCategory("Climbing", "figure.climbing", TransactionType.EXPENSE, "categoryPink"))
        val holiday = app.goalRepository.add(NewGoal("Holiday", BigDecimal("1500")))
        fun tx(id: String, amount: String, label: String, day: Instant, goalId: String? = null, categoryId: String? = null) =
            FinanceTransaction(id, day, BigDecimal(amount), "", label, categoryId, "EUR", goalId, null)
        listOf(
            tx("f1", "-100", "Food", at(2026, 8, 5)),
            tx("f2", "-200", "Food", at(2026, 8, 20)),
            tx("s", "2000", "Salary", at(2026, 9, 1)),
            tx("f3", "-60", "Food", at(2026, 9, 3)),
            tx("fun", "-50", "Fun", at(2026, 9, 5)),
            tx("t", "-500", "→ Holiday", at(2026, 9, 6), goalId = holiday.id),
            tx("f4", "-90", "Food", at(2026, 9, 8)),
            tx("c", "-35", "Climbing", at(2026, 9, 9), categoryId = climbing.id),
            tx("r", "-800", "Rent", at(2026, 9, 25)),
        ).forEach { app.transactionRepository.upsert(it) }
        app.transactionRepository.observeAll().first { it.size == 9 }
    }

    @After
    fun restoreLocale() = Locale.setDefault(previousLocale)

    private fun string(locale: Locale, id: Int) = CaptureHarness.localeContext(app, locale).getString(id)
    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    private fun shot(name: String) {
        rule.waitForIdle()
        CaptureHarness.writePng(rule, outputDir, name)
        CaptureHarness.writeSemantics(rule, outputDir, name)
    }

    @Test
    fun captureTheMatrix() {
        val cell = mutableStateOf(cells.first())
        rule.setContent {
            val current = cell.value
            Locale.setDefault(requireNotNull(current.locale))
            val context = CaptureHarness.localeContext(LocalContext.current, current.locale)
            val configuration = Configuration(context.resources.configuration).apply { fontScale = current.fontScale }
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(LocalDensity.current.density, current.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = current.theme) {
                    key(current.id) {
                        InsightsScreen(isDarkTheme = current.theme == ThemeMode.DARK, onToggleTheme = {}, onOpenSettings = {}, clock = clock)
                    }
                }
            }
        }
        cells.forEach { c ->
            cell.value = c
            val locale = requireNotNull(c.locale)
            val breakdown = hasText(string(locale, R.string.explorer_breakdown))
            waitFor(breakdown)
            rule.onNode(breakdown).performScrollTo()
            shot("explorer--${c.id}")

            // Popup windows: whole-screen captures (`captureToImage` sees one root).
            val september = java.time.format.DateTimeFormatter.ofPattern("LLL yyyy", locale).format(java.time.YearMonth.of(2026, 9))
            val periodButton = hasText(september) and hasClickAction()
            rule.onNode(periodButton).performClick()
            // A popup or dialog may re-provide the device's resources (parity-tests.md), so its copy is
            // matched in either language; the PNG shows which one it really rendered.
            fun either(id: Int) = hasText(string(locale, id)) or hasText(app.getString(id))
            waitFor(either(R.string.explorer_custom_range_menu))
            rule.waitForIdle()
            InstrumentationRegistry.getInstrumentation().uiAutomation.waitForIdle(500, 5_000) // past the enter animation
            CaptureHarness.writeScreenPng(outputDir, "menu--${c.id}")
            rule.onNode(either(R.string.explorer_custom_range_menu)).performClick()
            waitFor(either(R.string.explorer_apply))
            rule.waitForIdle()
            InstrumentationRegistry.getInstrumentation().uiAutomation.waitForIdle(500, 5_000)
            CaptureHarness.writeScreenPng(outputDir, "picker--${c.id}")
            rule.onNode(either(R.string.cancel) and hasClickAction()).performClick()
            rule.waitUntil(20_000) { rule.onAllNodes(either(R.string.explorer_apply)).fetchSemanticsNodes().isEmpty() }

            val food = hasContentDescription("Food") and hasClickAction()
            rule.onNode(food).performScrollTo()
            shot("rows--${c.id}")

            rule.onNode(food).performClick()
            waitFor(hasContentDescription(string(locale, R.string.back)))
            shot("drilldown--${c.id}")
            rule.onNode(hasContentDescription(string(locale, R.string.back)) and hasClickAction()).performClick()
            waitFor(breakdown)

            rule.onNode(hasText(string(locale, R.string.explorer_income)) and hasClickAction()).performScrollTo().performClick()
            rule.onNode(hasContentDescription(string(locale, R.string.explorer_previous))).performClick()
            rule.waitForIdle()
            shot("income-empty--${c.id}")
            // Back to September expenses for the next cell (the model outlives the cell's key).
            rule.onNode(hasContentDescription(string(locale, R.string.explorer_next))).performClick()
            rule.onNode(hasText(string(locale, R.string.explorer_expenses)) and hasClickAction()).performClick()
            rule.waitForIdle()
        }
    }
}
