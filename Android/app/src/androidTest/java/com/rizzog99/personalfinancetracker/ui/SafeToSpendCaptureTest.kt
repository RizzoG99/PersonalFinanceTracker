package com.rizzog99.personalfinancetracker.ui

import android.content.res.Configuration
import android.os.LocaleList
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.home.SAFE_TO_SPEND_HERO_TAG
import com.rizzog99.personalfinancetracker.features.home.SAFE_TO_SPEND_WHAT_IF_TAG
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * #298 step-7 evidence (plan D-08): Home's Safe to Spend card in every state, pulled from
 * `ui-safe-to-spend/`. The populated state (breakdown and what-if open) runs the full EN/IT ×
 * light/dark × compact/wide × font 1.0/2.0 matrix; every other state runs four cells. Same harness
 * guards as `GoalTransferCaptureTest`: wide cells only on a wide device, measured host width.
 */
@RunWith(Parameterized::class)
class SafeToSpendCaptureTest(private val state: State, private val cell: CaptureHarness.Cell) {

    enum class State { POPULATED, USING_BUFFER, OVER_PLAN, NO_INCOME_SPENT, NO_INCOME_HISTORY, NO_INCOME_EMPTY, HIDDEN }

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var original: Configuration? = null
    private val defaultLocale: Locale = Locale.getDefault()

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication

    private fun seed() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        app.preferencesRepository.setPayCycleStartDay(1)
        app.preferencesRepository.setSafeToSpendBufferPercent(5)
        app.preferencesRepository.setBaseCurrency("EUR")
        app.preferencesRepository.setHideBalance(state == State.HIDDEN)
        val now = Instant.now()
        val rows = when (state) {
            State.POPULATED, State.HIDDEN -> listOf("1000" to now, "-200" to now)
            State.USING_BUFFER -> listOf("1000" to now, "-980" to now)
            State.OVER_PLAN -> listOf("1000" to now, "-1020" to now)
            State.NO_INCOME_SPENT -> listOf("-200" to now)
            State.NO_INCOME_HISTORY -> listOf("500" to now.minus(45, ChronoUnit.DAYS))
            State.NO_INCOME_EMPTY -> emptyList()
        }
        rows.forEachIndexed { index, (amount, at) ->
            app.transactionRepository.upsert(
                FinanceTransaction(
                    id = "capture-$index", timestamp = at, amount = BigDecimal(amount), note = "Groceries",
                    categoryLabel = "Other", categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
                ),
            )
        }
    }

    @After
    @Suppress("DEPRECATION")
    fun restore() {
        Locale.setDefault(defaultLocale)
        original?.let { rule.activity.resources.updateConfiguration(it, rule.activity.resources.displayMetrics) }
        runBlocking { app.preferencesRepository.setHideBalance(false) }
    }

    @Test
    @Suppress("DEPRECATION")
    fun capture() {
        val deviceWidth = rule.activity.resources.configuration.screenWidthDp
        val wide = cell.widthDp >= 900
        assumeTrue("wide cells need a wide device", cell.widthDp <= deviceWidth)
        assumeTrue("compact cells run on the phone", wide || deviceWidth < 900)
        seed()

        val resources = rule.activity.resources
        original = Configuration(resources.configuration)
        val locale = cell.locale ?: Locale.ENGLISH
        resources.updateConfiguration(
            Configuration(resources.configuration).apply {
                setLocales(LocaleList(locale))
                fontScale = cell.fontScale
            },
            resources.displayMetrics,
        )
        Locale.setDefault(locale)
        val localized = CaptureHarness.localeContext(rule.activity, locale)
        fun string(id: Int) = localized.getString(id)

        rule.setContent {
            val configuration = Configuration(LocalConfiguration.current).apply { screenWidthDp = cell.widthDp }
            CompositionLocalProvider(LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = cell.theme) {
                    Box(Modifier.wrapContentWidth(Alignment.Start).width(cell.widthDp.dp).fillMaxHeight().testTag(HOST)) {
                        PersonalFinanceNavHost()
                    }
                }
            }
        }
        fun exists(matcher: SemanticsMatcher) = rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
        fun tap(matcher: SemanticsMatcher) = rule.onNode(matcher).performScrollTo().performClick()
        rule.waitUntil(20_000) { exists(hasText(string(R.string.safe_to_spend)) and isHeading()) }
        val hostWidth = with(rule.density) { rule.onNodeWithTag(HOST).fetchSemanticsNode().size.width.toDp().value }
        assertTrue("host is ${hostWidth}dp, cell says ${cell.widthDp}", abs(hostWidth - cell.widthDp) <= 1f)
        assertEquals(cell.fontScale, resources.configuration.fontScale)

        val dir = CaptureHarness.outputDir("ui-safe-to-spend")
        val name = "${state.name.lowercase()}-${cell.id}"
        val hasIncome = state in setOf(State.POPULATED, State.HIDDEN, State.USING_BUFFER, State.OVER_PLAN)
        if (hasIncome) rule.waitUntil(20_000) { exists(hasTestTag(SAFE_TO_SPEND_HERO_TAG)) }
        if (state == State.POPULATED || state == State.HIDDEN) {
            tap(hasText(string(R.string.safe_to_spend_how)) and hasClickAction())
            tap(hasText(string(R.string.what_if_title)) and hasClickAction())
            rule.waitUntil(20_000) { exists(hasSetTextAction()) }
            rule.onNode(hasSetTextAction()).performTextReplacement("100")
            rule.waitForIdle()
        }
        rule.onNode(hasText(string(R.string.safe_to_spend)) and isHeading()).performScrollTo()
        rule.waitForIdle()
        CaptureHarness.writePng(rule, dir, "$name-top")
        CaptureHarness.writeSemantics(rule, dir, name)
        if (state == State.POPULATED || state == State.HIDDEN) {
            // The outcome is the what-if section's last child: bring it fully into view.
            val outcome = rule.onAllNodes(hasAnyAncestor(hasTestTag(SAFE_TO_SPEND_WHAT_IF_TAG)))
            outcome[outcome.fetchSemanticsNodes().size - 1].performScrollTo()
            rule.waitForIdle()
            CaptureHarness.writePng(rule, dir, "$name-what-if")
        }
    }

    companion object {
        private const val HOST = "safeToSpendCaptureHost"

        private fun cell(locale: Locale?, theme: ThemeMode, width: Int, font: Float) = CaptureHarness.Cell(
            id = listOf(
                if (locale == null) "en" else "it",
                theme.name.lowercase(),
                if (width >= 900) "wide" else "compact",
                if (font > 1f) "large" else "default",
            ).joinToString("-"),
            locale = locale, widthDp = width, theme = theme, fontScale = font,
        )

        @JvmStatic
        @Parameterized.Parameters(name = "{0}-{index}")
        fun cells(): List<Array<Any>> = buildList {
            for (width in listOf(411, 900)) for (locale in listOf<Locale?>(null, Locale.ITALIAN)) {
                for (theme in listOf(ThemeMode.LIGHT, ThemeMode.DARK)) for (font in listOf(1f, 2f)) {
                    add(arrayOf(State.POPULATED, cell(locale, theme, width, font)))
                }
            }
            val four = listOf(
                cell(null, ThemeMode.LIGHT, 411, 1f),
                cell(Locale.ITALIAN, ThemeMode.DARK, 411, 2f),
                cell(null, ThemeMode.LIGHT, 900, 1f),
                cell(Locale.ITALIAN, ThemeMode.DARK, 900, 2f),
            )
            State.entries.filter { it != State.POPULATED }.forEach { state -> four.forEach { add(arrayOf(state, it)) } }
        }
    }
}
