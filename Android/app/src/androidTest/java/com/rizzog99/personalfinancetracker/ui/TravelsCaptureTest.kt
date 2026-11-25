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
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.navigation.seedTravelFixture
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.LocalDate
import java.time.format.DateTimeFormatter
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
 * #284 step-7 evidence: the Activity travel row, the Travels page, a travel's detail and the travel
 * form, across EN/IT × light/dark × compact/wide × font 1.0/2.0 (pull `ui-travels/`).
 *
 * Same harness as `ActivityBulkSelectionCaptureTest` (D-11 of #285): one cell per run, locale and font
 * on the activity's resources so sheets inherit them, wide cells only on a really wide device. The
 * formatters read the default locale, so each cell sets it too, and asserts the localized span and money.
 */
@RunWith(Parameterized::class)
class TravelsCaptureTest(private val cell: CaptureHarness.Cell) {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var original: Configuration? = null
    private val defaultLocale: Locale = Locale.getDefault()

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication

    @Before
    fun seed() {
        runBlocking { seedTravelFixture(app) }
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
        Locale.setDefault(locale)
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
        val row = hasContentDescription("Barcellona, ", substring = true) and hasClickAction()
        rule.waitUntil(20_000) { rule.onAllNodes(row).fetchSemanticsNodes().isNotEmpty() }
        val span = listOf("2026-09-12", "2026-09-16").map { LocalDate.parse(it).format(DateTimeFormatter.ofPattern("d MMM", locale)) }
        rule.onNode(row).assert(hasText("${plural(R.plurals.travel_expenses, 3)} · ${span[0]} – ${span[1]}"))
        rule.onNode(row).assert(hasText(formatSignedCurrency(BigDecimal("-230.00"), "EUR")))

        val dir = CaptureHarness.outputDir("ui-travels")
        CaptureHarness.writePng(rule, dir, "row-${cell.id}")
        CaptureHarness.writeSemantics(rule, dir, "row-${cell.id}")

        rule.onNode(hasContentDescription(string(R.string.travels_title)) and hasClickAction()).performClick()
        rule.waitUntil(20_000) { rule.onAllNodes(hasText("Montagna")).fetchSemanticsNodes().isNotEmpty() }
        CaptureHarness.writePng(rule, dir, "list-${cell.id}")
        CaptureHarness.writeSemantics(rule, dir, "list-${cell.id}")

        rule.onNode(row).performClick()
        rule.waitUntil(20_000) { rule.onAllNodes(hasText(string(R.string.travel_per_day))).fetchSemanticsNodes().isNotEmpty() }
        CaptureHarness.writePng(rule, dir, "detail-${cell.id}")
        CaptureHarness.writeSemantics(rule, dir, "detail-${cell.id}")

        rule.onNode(hasContentDescription(string(R.string.travel_options)) and hasClickAction()).performClick()
        rule.waitForIdle()
        rule.onNode(hasText(string(R.string.rename)) and hasClickAction()).performClick()
        val form = isRoot() and hasAnyDescendant(hasText(string(R.string.edit_travel)))
        rule.waitUntil(20_000) { rule.onAllNodes(form).fetchSemanticsNodes().isNotEmpty() }
        // The sheet is its own window, drawn in real time.
        Thread.sleep(1_500)
        rule.waitForIdle()
        CaptureHarness.writeScreenPng(dir, "form-${cell.id}")
        CaptureHarness.writeSemantics(rule, dir, "form-${cell.id}", root = rule.onNode(form, useUnmergedTree = true))
    }

    companion object {
        private const val HOST = "travelsCaptureHost"

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
