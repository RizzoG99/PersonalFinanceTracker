package com.rizzog99.personalfinancetracker.features.insights

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
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
 * #304 AC-01..04 and AC-06 on the real store through the production `InsightsScreen`, clock pinned to
 * fixture H: 15 Sep 2026 12:00 Europe/Rome, pay cycle day 1, en-US formatting.
 */
@RunWith(AndroidJUnit4::class)
class HealthScoreFlowTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private fun string(id: Int, vararg args: Any) = app.getString(id, *args)
    private val zone = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(at(9, 15), zone)
    private val previousLocale = Locale.getDefault()

    private fun at(m: Int, d: Int, h: Int = 12): Instant = LocalDateTime.of(2026, m, d, h, 0).atZone(zone).toInstant()

    @Before
    fun setUp(): Unit = runBlocking {
        Locale.setDefault(Locale.US)
        app.databaseProbed.first { it }
        app.pinLockRepository.state.first { it !is PinLock.Unknown }
        app.pinLockRepository.clearPin()
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        app.preferencesRepository.setPayCycleStartDay(1)
        app.preferencesRepository.setHealthScoreIgnoreSubscriptions(false)
        // Budgets on the two fixture categories; the seeded defaults carry none.
        val seeded = app.categoryRepository.observeAll().first()
        seeded.filter { it.monthlyBudget != null }.forEach { app.categoryRepository.update(it.copy(monthlyBudget = null)) }
        listOf("Groceries" to "300", "Dining" to "100").forEach { (name, budget) ->
            val existing = seeded.firstOrNull { it.name == name && it.type == TransactionType.EXPENSE }
            if (existing != null) {
                app.categoryRepository.update(existing.copy(monthlyBudget = BigDecimal(budget)))
            } else {
                app.categoryRepository.add(NewCategory(name, "cart", TransactionType.EXPENSE, "categoryGreen", BigDecimal(budget)))
            }
        }
        val budgeted = app.categoryRepository.observeAll().first { all -> all.count { it.monthlyBudget != null } == 2 }
        assertEquals(setOf("Groceries", "Dining"), budgeted.filter { it.monthlyBudget != null }.map { it.name }.toSet())
        fun tx(id: String, amount: String, label: String, day: Instant) =
            FinanceTransaction(id, day, BigDecimal(amount), "", label, null, "EUR", null, null)
        val rows = (4..9).map { tx("salary-$it", "1200", "Salary", at(it, 1)) } + listOf(
            tx("apr", "-1000", "Rent", at(4, 5)), tx("may", "-1200", "Rent", at(5, 5)), tx("jun", "-800", "Rent", at(6, 5)),
            tx("jul", "-1000", "Rent", at(7, 5)), tx("aug-rent", "-770", "Rent", at(8, 5)), tx("aug-stream", "-30", "Streaming", at(8, 20)),
            tx("aug-last", "-600", "Car repair", at(8, 31, 18)), tx("groceries", "-250", "Groceries", at(9, 3)),
            tx("dining", "-150", "Dining", at(9, 4)), tx("sep-stream", "-30", "Streaming", at(9, 10)), tx("sep-other", "-170", "Pharmacy", at(9, 12)),
        )
        rows.forEach { app.transactionRepository.upsert(it) }
        app.transactionRepository.observeAll().first { it.size == rows.size }
    }

    @After
    fun restore(): Unit = runBlocking {
        Locale.setDefault(previousLocale)
        app.preferencesRepository.setHealthScoreIgnoreSubscriptions(false)
    }

    private fun host() {
        rule.setContent {
            PersonalFinanceTheme { InsightsScreen(isDarkTheme = false, onToggleTheme = {}, onOpenSettings = {}, clock = clock) }
        }
        revealCard()
    }

    /** The card is the third item of Insights' lazy list: it exists only once scrolled into view. */
    private fun revealCard() {
        val list = hasScrollToIndexAction() and hasAnyDescendant(hasText(string(R.string.explorer_breakdown)))
        waitFor(list)
        rule.onNode(list).performScrollToNode(card)
        waitFor(card)
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    private val card get() = hasTestTag(HEALTH_CARD_TAG) and hasClickAction()

    @Test
    fun ac01_cardShows67() {
        host()
        waitFor(hasText("67 / 100"))
        rule.onNode(hasText(string(R.string.health_band_solid))).assertExists()
        listOf("Savings rate, 20 of 25", "Stability, 12 of 25", "Budget, 12 of 25", "Subscriptions, 23 of 25").forEach {
            rule.onNode(hasContentDescription(it)).assertExists()
        }
        rule.onNode(card).assertExists()
    }

    @Test
    fun ac03_detailExplainsAndAdvises() {
        host()
        waitFor(card)
        rule.onNode(card).performClick()
        listOf(
            "You saved 16% of income over the last 6 months.",
            "Save €39.00 more per month to reach the 20% target.",
            "Your monthly spending varies by 25%.",
            "1 of 2 budgeted categories are within limit this month.",
            "Bring 1 over-budget category within limit.",
            "Subscriptions are 1% of expenses over the last 6 months.",
            string(R.string.health_guide),
            string(R.string.health_exclude_subscriptions),
        ).forEach { waitFor(hasText(it)) }
        // AC-06: one switch node carrying its label and its state.
        val switch = rule.onNode(isToggleable() and hasText(string(R.string.health_exclude_subscriptions))).fetchSemanticsNode()
        assertEquals(ToggleableState.Off, switch.config.getOrNull(SemanticsProperties.ToggleableState))
        rule.onNode(hasText("Keep subscriptions under 15% of expenses to earn full points.")).assertExists()
    }

    @Test
    fun ac02_toggleRedistributesAndIsStored() {
        host()
        waitFor(card)
        rule.onNode(card).performClick()
        waitFor(isToggleable())
        // Below the breakdown inside the sheet: scroll the detail to it, as a user would, then tap.
        val exclude = isToggleable() and hasText(string(R.string.health_exclude_subscriptions))
        rule.onNode(hasScrollAction() and hasAnyDescendant(hasText(string(R.string.health_guide)))).performScrollToNode(exclude)
        rule.onNode(exclude).performClick()
        rule.waitUntil(20_000) { runBlocking { app.preferencesRepository.healthScoreIgnoreSubscriptions.first() } }
        waitFor(hasContentDescription("Savings rate, 27 of 34"))
        // The card behind the sheet and the sheet both show each component.
        waitFor(hasContentDescription("Stability, 15 of 33"))
        waitFor(hasContentDescription("Budget, 15 of 33"))
        assertTrue(rule.onAllNodes(hasContentDescription("Subscriptions", substring = true)).fetchSemanticsNodes().isEmpty())
        waitFor(hasText(string(R.string.health_band_progress)))
    }

    @Test
    fun ac04_snapshotAndHistory() {
        runBlocking {
            app.insightRepository.saveSnapshot(HealthScoreSnapshot("yesterday", at(9, 14), 60, 18, 12, 12, 18))
        }
        host()
        waitFor(card)
        rule.waitUntil(20_000) { runBlocking { app.insightRepository.recentSnapshots(6).size == 2 } }
        val today = runBlocking { app.insightRepository.recentSnapshots(6).first() }
        assertEquals(listOf(67, 20, 12, 12, 23), listOf(today.score, today.savingsScore, today.stabilityScore, today.adherenceScore, today.subscriptionScore))
        rule.onNode(card).performClick()
        waitFor(hasText(string(R.string.health_history)))
        rule.onNode(hasContentDescription("Sep 14, 2026, 60", substring = true)).assertExists()
        assertTrue(rule.onAllNodes(hasContentDescription(", 67", substring = true)).fetchSemanticsNodes().isNotEmpty())
    }

    /** Capture cells (AC-06): card and detail, EN, light/dark, 100/200 % text; the sheet is its own window. */
    @Test
    fun captureMatrix() {
        val cell = androidx.compose.runtime.mutableStateOf(Triple("light-100", com.rizzog99.personalfinancetracker.ui.theme.ThemeMode.LIGHT, 1f))
        rule.setContent {
            val (_, theme, scale) = cell.value
            val density = androidx.compose.ui.platform.LocalDensity.current
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density, scale)) {
                PersonalFinanceTheme(themeMode = theme) {
                    androidx.compose.runtime.key(cell.value.first) {
                        InsightsScreen(isDarkTheme = theme == com.rizzog99.personalfinancetracker.ui.theme.ThemeMode.DARK, onToggleTheme = {}, onOpenSettings = {}, clock = clock)
                    }
                }
            }
        }
        val dir = com.rizzog99.personalfinancetracker.ui.CaptureHarness.outputDir("health-score-304")
        listOf(
            Triple("light-100", com.rizzog99.personalfinancetracker.ui.theme.ThemeMode.LIGHT, 1f),
            Triple("dark-100", com.rizzog99.personalfinancetracker.ui.theme.ThemeMode.DARK, 1f),
            Triple("light-200", com.rizzog99.personalfinancetracker.ui.theme.ThemeMode.LIGHT, 2f),
            Triple("dark-200", com.rizzog99.personalfinancetracker.ui.theme.ThemeMode.DARK, 2f),
        ).forEach { c ->
            cell.value = c
            revealCard()
            rule.waitForIdle()
            com.rizzog99.personalfinancetracker.ui.CaptureHarness.writePng(rule, dir, "card--en-${c.first}")
            com.rizzog99.personalfinancetracker.ui.CaptureHarness.writeSemantics(rule, dir, "card--en-${c.first}")
            rule.onNode(card).performClick()
            waitFor(isToggleable() and hasText(string(R.string.health_exclude_subscriptions)))
            InstrumentationRegistry.getInstrumentation().uiAutomation.waitForIdle(500, 5_000)
            com.rizzog99.personalfinancetracker.ui.CaptureHarness.writeScreenPng(dir, "detail--en-${c.first}")
            // The next cell re-keys the screen, which drops the open sheet with it.
        }
    }
}
