package com.rizzog99.personalfinancetracker.features.insights

import android.app.LocaleManager
import android.os.Build
import android.os.LocaleList
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import java.math.BigDecimal
import java.time.Instant
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
 * #304 on the real activity: AC-05, the wide drawer's Health Score page (tablet AVD), and AC-03/06's
 * detail sheet in Italian under the real per-app locale (a sheet re-provides its own resources).
 */
@RunWith(AndroidJUnit4::class)
class HealthScoreActivityTest {

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
                app.preferencesRepository.setPayCycleStartDay(1)
                app.preferencesRepository.setHealthScoreIgnoreSubscriptions(false)
            }
        })
        .around(rule)

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication
    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }
    private fun item(label: String) = hasText(label) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
    private fun seedActivity() = runBlocking {
        val now = Instant.now()
        app.transactionRepository.upsert(FinanceTransaction("in", now, BigDecimal("1000"), "", "Salary", null, "EUR", null, null))
        app.transactionRepository.upsert(FinanceTransaction("out", now, BigDecimal("-500"), "", "Rent", null, "EUR", null, null))
    }

    /** Evidence only: `UiAutomation.takeScreenshot()` returns null before API 33 (as `RelockCaptureTest`, D-02). */
    private fun captureScreen(name: String) {
        if (Build.VERSION.SDK_INT >= 33) CaptureHarness.writeScreenPng(CaptureHarness.outputDir("health-score-304"), name)
    }

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).use { pfd ->
            java.io.FileInputStream(pfd.fileDescriptor).use { it.readBytes() }
        }
    }

    @After
    fun restoreLocale() {
        shell("settings put system font_scale 1.0")
        if (Build.VERSION.SDK_INT >= 33) {
            instrumentation.targetContext.getSystemService(LocaleManager::class.java).applicationLocales = LocaleList.getEmptyLocaleList()
        }
    }

    @Test
    fun ac05_wideDrawerOpensHealthScore() {
        val wide = rule.activity.resources.configuration.screenWidthDp >= 840
        assumeTrue("the drawer is the wide layout's", wide)
        val entry = item(app.getString(R.string.health_score))
        waitFor(entry)
        rule.onNode(entry).performClick()
        // No activity yet: the empty state, as iOS's "No Health Score Yet".
        waitFor(hasText(app.getString(R.string.health_score_empty)))

        seedActivity()
        waitFor(hasText(app.getString(R.string.health_score_out_of)))
        waitFor(hasText(app.getString(R.string.health_exclude_subscriptions)))
        captureScreen("wide-page--${Build.MODEL.replace(' ', '_')}")
    }

    @Test
    fun ac03_detailSpeaksItalian() {
        assumeTrue("per-app locales need API 33+", Build.VERSION.SDK_INT >= 33)
        seedActivity()
        instrumentation.targetContext.getSystemService(LocaleManager::class.java).applicationLocales = LocaleList(Locale.ITALIAN)
        rule.waitUntil(20_000) {
            var italian = false
            runCatching { rule.activityRule.scenario.onActivity { italian = it.resources.configuration.locales[0].language == "it" } }
            italian && rule.activityRule.scenario.state == Lifecycle.State.RESUMED
        }
        rule.waitForIdle()
        val it = CaptureHarness.localeContext(instrumentation.targetContext, Locale.ITALIAN)
        rule.onNode(item(it.getString(R.string.tab_insights))).performClick()
        // Income 1000, spending 500: 50 % saved → savings 25, a "Solid" or better band.
        val card = hasTestTag(HEALTH_CARD_TAG) and hasClickAction()
        // The card is the third item of Insights' lazy list: scroll the list to it.
        val list = hasScrollToIndexAction() and hasAnyDescendant(hasText(it.getString(R.string.explorer_breakdown)))
        waitFor(list)
        rule.onNode(list).performScrollToNode(card)
        waitFor(card)
        rule.onNode(card).performClick()
        listOf(
            it.getString(R.string.health_explain_savings, 50),
            it.getString(R.string.health_guide),
            it.getString(R.string.health_exclude_subscriptions),
            it.getString(R.string.health_explain_budget_none),
        ).forEach { text -> waitFor(hasText(text)) }
        instrumentation.uiAutomation.waitForIdle(500, 5_000)
        captureScreen("sheet-it--${Build.MODEL.replace(' ', '_')}")
    }

    /** AC-06: the sheet is its own window, so 200 % text is proven with the system font scale. */
    @Test
    fun ac06_sheetAtLargeText() {
        seedActivity()
        shell("settings put system font_scale 2.0")
        rule.waitUntil(20_000) {
            var scaled = false
            runCatching { rule.activityRule.scenario.onActivity { scaled = it.resources.configuration.fontScale == 2f } }
            scaled && rule.activityRule.scenario.state == Lifecycle.State.RESUMED
        }
        rule.waitForIdle()
        rule.onNode(item(app.getString(R.string.tab_insights))).performClick()
        val card = hasTestTag(HEALTH_CARD_TAG) and hasClickAction()
        val list = hasScrollToIndexAction() and hasAnyDescendant(hasText(app.getString(R.string.explorer_breakdown)))
        waitFor(list)
        rule.onNode(list).performScrollToNode(card)
        waitFor(card)
        captureScreen("card-200--${Build.MODEL.replace(' ', '_')}")
        rule.onNode(card).performClick()
        waitFor(hasText(app.getString(R.string.health_guide)))
        instrumentation.uiAutomation.waitForIdle(500, 5_000)
        captureScreen("sheet-200--${Build.MODEL.replace(' ', '_')}")
    }
}
