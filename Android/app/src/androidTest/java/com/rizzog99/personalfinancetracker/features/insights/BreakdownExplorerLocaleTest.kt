package com.rizzog99.personalfinancetracker.features.insights

import android.app.LocaleManager
import android.os.Build
import android.os.LocaleList
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #303 AC-09 code review r1: the explorer's popups (period menu, date-range dialog) in Italian under
 * the real per-app locale. The capture matrix's local override stops at a popup's edge, so this is
 * where their copy is proven. Needs per-app locales (API 33+).
 */
@RunWith(AndroidJUnit4::class)
class BreakdownExplorerLocaleTest {

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.databaseProbed.first { it }
                app.pinLockRepository.state.first { it !is PinLock.Unknown }
                app.pinLockRepository.clearPin()
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
            }
        })
        .around(rule)

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication
    private fun italian(id: Int) = CaptureHarness.localeContext(instrumentation.targetContext, Locale.ITALIAN).getString(id)
    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    @After
    fun restoreLocale() {
        if (Build.VERSION.SDK_INT >= 33) {
            instrumentation.targetContext.getSystemService(LocaleManager::class.java).applicationLocales = LocaleList.getEmptyLocaleList()
        }
    }

    @Test
    fun ac09_popupsSpeakItalian() {
        assumeTrue("per-app locales need API 33+", Build.VERSION.SDK_INT >= 33)
        instrumentation.targetContext.getSystemService(LocaleManager::class.java).applicationLocales = LocaleList(Locale.ITALIAN)
        rule.waitUntil(20_000) {
            var italian = false
            runCatching { rule.activityRule.scenario.onActivity { italian = it.resources.configuration.locales[0].language == "it" } }
            italian && rule.activityRule.scenario.state == Lifecycle.State.RESUMED
        }
        rule.waitForIdle()

        rule.onNode(hasText(italian(R.string.tab_insights)) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)).performClick()
        val month = DateTimeFormatter.ofPattern("LLL yyyy", Locale.ITALIAN).format(YearMonth.now())
        waitFor(hasText(month) and hasClickAction())
        rule.onNode(hasText(month) and hasClickAction()).performClick()

        listOf(R.string.explorer_week, R.string.explorer_month, R.string.explorer_year, R.string.explorer_custom_range_menu)
            .forEach { waitFor(hasText(italian(it))) }
        val dir = CaptureHarness.outputDir("breakdown-explorer-303")
        instrumentation.uiAutomation.waitForIdle(500, 5_000)
        CaptureHarness.writeScreenPng(dir, "menu--it-real-locale")

        rule.onNode(hasText(italian(R.string.explorer_custom_range_menu))).performClick()
        listOf(R.string.explorer_custom_range, R.string.explorer_apply, R.string.cancel).forEach { waitFor(hasText(italian(it))) }
        instrumentation.uiAutomation.waitForIdle(500, 5_000)
        CaptureHarness.writeScreenPng(dir, "picker--it-real-locale")
        rule.onNode(hasText(italian(R.string.cancel)) and hasClickAction()).performClick()
    }
}
