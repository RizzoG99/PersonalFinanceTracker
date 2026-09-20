package com.rizzog99.personalfinancetracker.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * Parity `M1-UI-STATES` (#111): can a user actually *reach* these states in the shipping app?
 *
 * `UiStateEvidenceTest` proves each state renders correctly once chosen. That is not the same
 * claim — a component tested only in a host the test built proves nothing about reachability. This
 * suite drives the production `MainActivity`, the real startup gates, the real repositories and the
 * real navigation shell, and asserts the states appear by themselves.
 *
 * Only the two states reachable without breaking the store are covered here. Reaching the error
 * state on-device would need a seam to fail a Room read mid-session, and #111 declined to add a
 * production hook purely for that; its coverage is the JVM state machine plus the rendered
 * production `when`. Recorded as a limitation on the issue rather than papered over.
 */
@RunWith(AndroidJUnit4::class)
class UiStateReachabilityTest {

    private val composeRule = createAndroidComposeRule<MainActivity>()

    /**
     * Ordered outside the activity rule, exactly as the #110 suites do: `AppBootEvidenceTest`
     * deliberately leaves a PIN on the device, and without clearing it first the whole
     * instrumentation run becomes order-dependent.
     */
    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                application.pinLockRepository.clearPin()
                // AC-02 is about a *genuinely* empty ledger, so the fixture has to be the absence
                // of rows rather than a filter that hides them — otherwise the test would prove
                // nothing about the first-run/no-results distinction it exists to check.
                application.transactionRepository.observeAll().first()
                    .forEach { application.transactionRepository.delete(it.id) }
            }
        })
        .around(composeRule)

    private val application: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as PersonalFinanceApplication

    private fun string(id: Int): String =
        InstrumentationRegistry.getInstrumentation().targetContext.getString(id)

    @Before
    fun openActivityTab() {
        composeRule.waitForIdle()
        composeRule.onNodeWithText(string(R.string.tab_activity)).performClick()
        composeRule.waitForIdle()
    }

    /** AC-02: a genuinely empty ledger reaches the first-run state, action included. */
    @Test
    fun ac02_aFreshInstallReachesTheFirstRunEmptyState() {
        composeRule.onNodeWithText(string(R.string.empty_state_title))
            .performScrollTo()
            .assertIsDisplayed()
        composeRule.onNodeWithText(string(R.string.add_transaction))
            .performScrollTo()
            .assertIsDisplayed()

        assertEquals(
            "and it is not the no-results state",
            0,
            composeRule.onAllNodes(hasText(string(R.string.no_matching_transactions)))
                .fetchSemanticsNodes().size,
        )
    }

    /** AC-03: with data present, a query that matches nothing reaches the no-results state. */
    @Test
    fun ac03_aQueryOverRealDataReachesTheNoResultsStateAndClearsBackOut() {
        runBlocking {
            application.transactionRepository.upsert(
                FinanceTransaction(
                    id = UUID.randomUUID().toString(),
                    timestamp = Instant.now(),
                    amount = BigDecimal("-12.50"),
                    note = "coffee",
                    categoryLabel = "Food",
                    categoryId = null,
                    currencyCode = "EUR",
                    goalId = null,
                    recurrenceRuleId = null,
                ),
            )
        }
        composeRule.waitForIdle()

        composeRule.onNode(hasSetTextAction()).performTextInput("zzzz-no-such-note")
        composeRule.waitForIdle()

        composeRule.onNodeWithText(string(R.string.no_matching_transactions))
            .performScrollTo()
            .assertIsDisplayed()
        assertEquals(
            "underlying data exists, so the first-run copy must not appear",
            0,
            composeRule.onAllNodes(hasText(string(R.string.empty_state_title)))
                .fetchSemanticsNodes().size,
        )

        // AC-03's recovery must change the real filter state, not just hide the message.
        composeRule.onNodeWithText(string(R.string.clear_search_and_filters))
            .performScrollTo()
            .performClick()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("coffee").performScrollTo().assertIsDisplayed()
        assertEquals(
            0,
            composeRule.onAllNodes(hasText(string(R.string.no_matching_transactions)))
                .fetchSemanticsNodes().size,
        )
    }
}
