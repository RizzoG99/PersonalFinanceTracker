package com.rizzog99.personalfinancetracker.features

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #298 AC-10 on the production activity: the buffer chosen in Settings survives an activity
 * recreation and still drives Home. Setup runs outside the activity rule (as `NavShellEvidenceTest`):
 * the PIN is cleared and the store seeded before `MainActivity` launches.
 */
@RunWith(AndroidJUnit4::class)
class SafeToSpendRecreationTest {

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.pinLockRepository.clearPin()
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                app.preferencesRepository.setPayCycleStartDay(1)
                app.preferencesRepository.setSafeToSpendBufferPercent(5)
                app.preferencesRepository.setHideBalance(false)
                app.preferencesRepository.setBaseCurrency("EUR")
                listOf("1000", "-200").forEachIndexed { index, amount ->
                    app.transactionRepository.upsert(
                        FinanceTransaction(
                            id = "recreate-$index", timestamp = Instant.now(), amount = BigDecimal(amount), note = "",
                            categoryLabel = "Other", categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
                        ),
                    )
                }
            }
        })
        .around(rule)

    private fun string(id: Int, vararg args: Any) = app.getString(id, *args)
    private fun waitFor(condition: () -> Boolean) = rule.waitUntil(20_000, condition)
    private fun exists(matcher: SemanticsMatcher) = rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
    private fun euro(amount: String) = formatCurrency(BigDecimal(amount), "EUR")

    @Test
    fun ac10_bufferSurvivesRecreationAndDrivesHome() {
        waitFor { exists(hasText(euro("750"))) }

        rule.onNode(hasContentDescription(string(R.string.settings_title)) and hasClickAction()).performClick()
        val minus = hasContentDescription(string(R.string.decrease_safety_buffer))
        waitFor { exists(hasText(string(R.string.safety_buffer_value, 5))) }
        repeat(5) { rule.onNode(minus).performScrollTo().performClick() }
        waitFor { exists(hasText(string(R.string.safety_buffer_value, 0))) }

        rule.activityRule.scenario.recreate()

        // Settings visibility is saved state (PersonalFinanceNavHost), so it comes back open.
        waitFor { exists(hasText(string(R.string.safety_buffer_value, 0))) }
        rule.onNode(hasContentDescription(string(R.string.back)) and hasClickAction()).performClick()
        // 1000 − 200 with no buffer.
        waitFor { exists(hasText(euro("800"))) }
    }
}
