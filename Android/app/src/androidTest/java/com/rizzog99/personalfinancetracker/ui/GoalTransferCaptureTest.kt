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
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasAnySibling
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.features.activity.ACTIVITY_SEARCH_TAG
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * #300 step-7 evidence: the editor on Transfer with a goal chosen and Repeat on, across EN/IT ×
 * light/dark × compact/wide × font 1.0/2.0 (pull `ui-goal-transfer/`). Same harness as
 * `TravelsCaptureTest`: compact is the real modal sheet, wide is Activity's right-pane editor.
 */
@RunWith(Parameterized::class)
class GoalTransferCaptureTest(private val cell: CaptureHarness.Cell) {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var original: Configuration? = null
    private val defaultLocale: Locale = Locale.getDefault()

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication

    @Before
    fun seed() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        app.goalRepository.add(NewGoal("Emergency fund", BigDecimal("5000")))
        app.goalRepository.add(NewGoal("Holiday", BigDecimal("1500")))
        Unit
    }

    @After
    @Suppress("DEPRECATION")
    fun restore() {
        Locale.setDefault(defaultLocale)
        original?.let { rule.activity.resources.updateConfiguration(it, rule.activity.resources.displayMetrics) }
    }

    @Test
    @Suppress("DEPRECATION")
    fun capture() {
        val deviceWidth = rule.activity.resources.configuration.screenWidthDp
        val wide = cell.widthDp >= 900
        assumeTrue("wide cells need a wide device", cell.widthDp <= deviceWidth)
        assumeTrue("compact cells run on the phone", wide || deviceWidth < 900)

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
        rule.waitForIdle()
        val hostWidth = with(rule.density) { rule.onNodeWithTag(HOST).fetchSemanticsNode().size.width.toDp().value }
        assertTrue("host is ${hostWidth}dp, cell says ${cell.widthDp}", abs(hostWidth - cell.widthDp) <= 1f)
        assertEquals(cell.fontScale, resources.configuration.fontScale)

        with(NavShellMarkers(locale)) { rule.selectTab(activityTab) }
        fun exists(matcher: SemanticsMatcher) = rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
        fun tap(matcher: SemanticsMatcher) = rule.onNode(matcher).performScrollTo().performClick()
        val editorTitle = hasText(string(R.string.add_transaction)) and isHeading()
        if (!wide) tap(hasContentDescription(string(R.string.add_transaction)) and hasClickAction())
        val transfer = hasText(string(R.string.transaction_type_transfer)) and hasClickAction()
        rule.waitUntil(20_000) { exists(transfer) }
        // Wide: the always-visible pane, never a second (modal) editor.
        rule.onAllNodes(editorTitle).assertCountEquals(1)

        rule.onAllNodes(hasSetTextAction() and !hasTestTag(ACTIVITY_SEARCH_TAG))[0].performTextReplacement("200")
        tap(transfer)
        val goal = hasText("Emergency fund") and hasClickAction()
        rule.waitUntil(20_000) { exists(goal) }
        tap(goal)
        tap(isToggleable() and hasAnySibling(hasText(string(R.string.repeat_transaction))))
        tap(hasText(string(R.string.recurrence_monthly)) and hasClickAction())
        rule.onNode(goal).assertIsSelected()
        rule.onNode(transfer).assertIsSelected()
        assertTrue("localized Goal header", exists(hasText(string(R.string.transaction_goal_header))))
        rule.onNode(transfer).performScrollTo()
        rule.waitForIdle()

        val dir = CaptureHarness.outputDir("ui-goal-transfer")
        if (wide) {
            CaptureHarness.writePng(rule, dir, "editor-${cell.id}")
            CaptureHarness.writeSemantics(rule, dir, "editor-${cell.id}")
        } else {
            // The sheet is its own window, drawn in real time.
            Thread.sleep(1_500)
            rule.waitForIdle()
            CaptureHarness.writeScreenPng(dir, "editor-${cell.id}")
            val sheet = isRoot() and hasAnyDescendant(editorTitle)
            CaptureHarness.writeSemantics(rule, dir, "editor-${cell.id}", root = rule.onNode(sheet, useUnmergedTree = true))
        }
    }

    companion object {
        private const val HOST = "goalTransferCaptureHost"

        @JvmStatic
        @Parameterized.Parameters(name = "{index}")
        fun cells(): List<CaptureHarness.Cell> = buildList {
            for (width in listOf(411, 900)) for (locale in listOf<Locale?>(null, Locale.ITALIAN)) {
                for (theme in listOf(ThemeMode.LIGHT, ThemeMode.DARK)) for (font in listOf(1f, 2f)) {
                    val id = listOf(
                        if (locale == null) "en" else "it",
                        theme.name.lowercase(),
                        if (width >= 900) "wide" else "compact",
                        if (font > 1f) "large" else "default",
                    ).joinToString("-")
                    add(CaptureHarness.Cell(id, locale = locale, widthDp = width, theme = theme, fontScale = font))
                }
            }
        }
    }
}
