package com.rizzog99.personalfinancetracker.navigation

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
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
 * #283 AC-02/AC-05: editor and selection state survive a real Activity recreation on
 * [MainActivity] (the FoundationLocaleRecreationTest pattern: PIN cleared before launch).
 * Phone tests run on any device; the wide ones need a really wide device (Pixel_Tablet) and skip
 * elsewhere, since `MainActivity` reads the real configuration.
 */
@RunWith(AndroidJUnit4::class)
class PlanRecreationTest {

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
            }
        })
        .around(rule)

    @After
    fun tearDown() = runBlocking { app.pinLockRepository.clearPin() }

    private fun string(id: Int) = InstrumentationRegistry.getInstrumentation().targetContext.getString(id)
    private val anyTab = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)
    private fun tab(label: String) = hasText(label) and anyTab
    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }
    private fun waitGone(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isEmpty() }

    private fun recreate() {
        rule.activityRule.scenario.recreate()
        rule.waitForIdle()
    }

    private val isWide: Boolean get() = rule.activity.resources.configuration.screenWidthDp >= 840

    @Test
    fun ac02_anOpenGoalEditorOnPlanSurvivesRecreationAndBackClosesIt() {
        assumeTrue("compact layout", !isWide)
        waitFor(tab(string(R.string.tab_plan)))
        rule.onNode(tab(string(R.string.tab_plan))).performClick()
        waitFor(hasText(string(R.string.plan_welcome_title)))
        rule.onNode(hasText(string(R.string.add_goal)) and hasClickAction()).performScrollTo().performClick()
        val editorSave = hasContentDescription(string(R.string.add_goal))
        waitFor(editorSave)

        recreate()

        waitFor(editorSave)
        Espresso.pressBack()
        waitGone(editorSave)
        waitFor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG))
        rule.onNode(tab(string(R.string.tab_plan))).assertIsSelected()
    }

    @Test
    fun ac05_wideDrawerSelectionSurvivesRecreation() {
        assumeTrue("needs a wide device (Pixel_Tablet)", isWide)
        waitFor(tab(string(R.string.budgets_title)))
        rule.onNode(tab(string(R.string.budgets_title))).performClick()
        rule.waitForIdle()
        rule.onNode(tab(string(R.string.budgets_title))).assertIsSelected()

        recreate()

        waitFor(tab(string(R.string.budgets_title)))
        rule.onNode(tab(string(R.string.budgets_title))).assertIsSelected()
    }

    @Test
    fun ac05_wideRecurringEditorSurvivesRecreationAndStaysDismissed() {
        assumeTrue("needs a wide device (Pixel_Tablet)", isWide)
        val zone = ZoneId.systemDefault()
        runBlocking {
            val expense = app.categoryRepository.observeAll().first().first { it.type == TransactionType.EXPENSE }
            app.recurrenceRepository.create(
                NewRecurrenceRule(
                    frequency = RecurrenceFrequency.MONTHLY, interval = 1,
                    startDate = LocalDate.now(zone).plusDays(3).atTime(10, 0).atZone(zone).toInstant(),
                    amount = BigDecimal("-13.00"), note = "Netflix", categoryLabel = expense.name, categoryId = expense.id,
                    currencyCode = "EUR",
                ),
            )
        }
        // Wide has no Plan item; the Recurring destination is where rules are edited.
        waitFor(tab(string(R.string.recurring_title)))
        rule.onNode(tab(string(R.string.recurring_title))).performClick()
        waitFor(hasText("Netflix"))
        rule.onNode(hasText("Netflix") and hasClickAction()).performClick()
        val editor = hasSetTextAction() and hasText("Netflix")
        waitFor(editor)

        recreate()
        waitFor(editor)

        Espresso.pressBack()
        waitGone(editor)
        recreate()
        rule.waitForIdle()
        waitFor(hasText("Netflix"))
        rule.onAllNodes(editor).fetchSemanticsNodes().let { assert(it.isEmpty()) { "dismissed editor came back" } }
    }
}
