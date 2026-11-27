package com.rizzog99.personalfinancetracker.features.insights

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.security.AppLockSession
import java.math.BigDecimal
import java.time.Instant
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #303 AC-07 on the real activity: the period the user picked survives a tab switch, a data change
 * and a background → PIN relock → unlock (iOS keeps it on the long-lived model, `InsightsViewModel.swift:12-17`).
 */
@RunWith(AndroidJUnit4::class)
class BreakdownExplorerRetentionTest {

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.databaseProbed.first { it }
                app.pinLockRepository.state.first { it !is PinLock.Unknown }
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                app.preferencesRepository.setBiometricEnabled(false)
                app.pinLockRepository.setPin(hash = PinCodec.hash(PIN, SALT), salt = SALT)
                expense("old", Instant.now().minus(40, ChronoUnit.DAYS))
            }
        })
        .around(rule)

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private var now = 1_000_000L

    private suspend fun expense(id: String, at: Instant) = app.transactionRepository.upsert(
        FinanceTransaction(id, at, BigDecimal("-12.00"), "", "Food", null, "EUR", null, null),
    )

    @After
    fun clearPin(): Unit = runBlocking { app.pinLockRepository.clearPin() }

    private fun string(id: Int) = app.getString(id)
    private fun shown(matcher: SemanticsMatcher) = rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
    private fun waitFor(matcher: SemanticsMatcher) = rule.waitUntil(DEADLINE) { shown(matcher) }
    private val pinTitle get() = hasText(string(R.string.pin_unlock_title))
    private fun key(digit: Char) =
        hasText(digit.toString()) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)

    private fun unlock() {
        waitFor(pinTitle)
        PIN.forEach { rule.onNode(key(it)).performClick() }
        rule.waitUntil(DEADLINE) { !shown(pinTitle) }
    }

    private fun selectTab(id: Int) {
        rule.onNode(hasText(string(id)) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)).performClick()
        rule.waitForIdle()
    }

    @Test
    fun ac07_periodSurvivesTabSwitchDataChangeAndRelock() {
        rule.activityRule.scenario.onActivity { ViewModelProvider(it)[AppLockSession::class.java].clock = { now } }
        unlock()
        selectTab(R.string.tab_insights)
        val format = DateTimeFormatter.ofPattern("LLL yyyy", Locale.getDefault())
        waitFor(hasText(format.format(YearMonth.now())))

        rule.onNode(hasContentDescription(string(R.string.explorer_previous))).performClick()
        val chosen = hasText(format.format(YearMonth.now().minusMonths(1)))
        waitFor(chosen)

        selectTab(R.string.tab_home)
        selectTab(R.string.tab_insights)
        waitFor(chosen)

        runBlocking { expense("new", Instant.now()) }
        rule.waitForIdle()
        waitFor(chosen)

        rule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        now += 30_000
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        unlock()
        waitFor(chosen)
    }

    private companion object {
        const val PIN = "123456"
        const val SALT = "explorer-retention-salt"
        const val DEADLINE = 20_000L
    }
}
