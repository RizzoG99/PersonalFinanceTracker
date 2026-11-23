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
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.features.activity.BULK_ACTION_BAR_TAG
import com.rizzog99.personalfinancetracker.features.activity.BULK_INPUT_TAG
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.navigation.seedBulkFixture
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
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
 * #285 step-7 evidence: selection mode and the Amount sheet across EN/IT × light/dark × compact/wide
 * × font 1.0/2.0 (pull `ui-bulk-selection/`).
 *
 * One cell per test run, so each starts from fresh content (D-11). Locale and font scale go on the
 * activity's own resources, not composition locals: the sheet is its own window, whose `ComposeView`
 * reads that context, so a local override would stop at its edge (`SaveFeedbackTest`). Wide cells
 * run only on a device that is really wide (Pixel_Tablet): a 900 dp host on a phone is squeezed (#376).
 */
@RunWith(Parameterized::class)
class ActivityBulkSelectionCaptureTest(private val cell: CaptureHarness.Cell) {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var original: Configuration? = null

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication

    @Before
    fun seed() {
        runBlocking { seedBulkFixture(app) }
    }

    @After
    @Suppress("DEPRECATION")
    fun restoreConfiguration() {
        original?.let { rule.activity.resources.updateConfiguration(it, rule.activity.resources.displayMetrics) }
    }

    @Test
    @Suppress("DEPRECATION")
    fun capture() {
        val deviceWidth = rule.activity.resources.configuration.screenWidthDp
        assumeTrue("wide cells need a wide device", cell.widthDp <= deviceWidth)
        assumeTrue("compact cells run on the phone", cell.widthDp >= 900 || deviceWidth < 900)

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
        val localized = CaptureHarness.localeContext(rule.activity, locale)
        fun string(id: Int) = localized.getString(id)
        fun plural(id: Int, n: Int) = localized.resources.getQuantityString(id, n, n)

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
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Caffè bar")).fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("Caffè bar").performScrollTo().performTouchInput { longClick() }
        rule.waitForIdle()
        rule.onNode(isToggleable() and hasText("Caffè casa", substring = true)).performScrollTo().performClick()
        rule.waitUntil(20_000) { rule.onAllNodes(hasText(plural(R.plurals.selection_count, 2))).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(hasText(string(R.string.bulk_amount)) and hasAnyAncestor(hasTestTag(BULK_ACTION_BAR_TAG))).assertExists()

        val dir = CaptureHarness.outputDir("ui-bulk-selection")
        CaptureHarness.writePng(rule, dir, "selection-${cell.id}")
        CaptureHarness.writeSemantics(rule, dir, "selection-${cell.id}")

        rule.onNode(hasText(string(R.string.bulk_amount)) and hasClickAction() and hasAnyAncestor(hasTestTag(BULK_ACTION_BAR_TAG)))
            .performClick()
        val sheet = isRoot() and hasAnyDescendant(hasTestTag(BULK_INPUT_TAG))
        rule.waitUntil(20_000) { rule.onAllNodes(sheet).fetchSemanticsNodes().isNotEmpty() }
        // The sheet is its own window, drawn in real time: let its enter animation and the keyboard settle.
        Thread.sleep(1_500)
        rule.waitForIdle()
        // The sheet window carries the cell's locale: its own copy is localized.
        rule.onNode(sheet and hasAnyDescendant(hasText(string(R.string.bulk_new_amount)))).assertExists()
        rule.onNode(sheet and hasAnyDescendant(hasText(string(R.string.bulk_set)))).assertExists()
        val sheetWidth = with(rule.density) { rule.onNode(sheet).fetchSemanticsNode().size.width.toDp().value }
        assertTrue("sheet is ${sheetWidth}dp on a ${deviceWidth}dp device", sheetWidth <= deviceWidth + 1)
        CaptureHarness.writeScreenPng(dir, "amount-${cell.id}")
        CaptureHarness.writeSemantics(rule, dir, "amount-${cell.id}", root = rule.onNode(sheet, useUnmergedTree = true))
    }

    companion object {
        private const val HOST = "bulkCaptureHost"

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
