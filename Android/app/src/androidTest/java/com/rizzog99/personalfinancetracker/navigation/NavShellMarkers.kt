package com.rizzog99.personalfinancetracker.navigation

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.R
import org.junit.Assert.assertTrue

/**
 * Shared vocabulary for the #110 (`M1-NAV-SHELL`) navigation-shell evidence suites.
 *
 * The two rules a marker here has to satisfy, both learned the hard way:
 *
 * 1. **It must not be the tab label.** `Activity` and `Insights` are each a tab label *and* that
 *    screen's top-bar title, so matching the label alone cannot tell "the tab exists" from "the
 *    screen is shown" — and every absence assertion would be trivially false.
 * 2. **It must not depend on destination state.** The Activity search box looked like the obvious
 *    marker until the AC-03/AC-05 tests typed into it: its placeholder disappears the moment there
 *    is text, so the marker would vanish exactly when the test needs it. The filter action is in the
 *    Activity top bar in both the compact and the two-pane variant and never moves.
 */
class NavShellMarkers(
    private val locale: java.util.Locale? = null,
) {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext.let { base ->
        locale?.let {
            val configuration = android.content.res.Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(it)) }
            base.createConfigurationContext(configuration)
        } ?: base
    }

    private fun string(id: Int) = context.getString(id)

    val homeTab: String get() = string(R.string.tab_home)
    val activityTab: String get() = string(R.string.tab_activity)
    val insightsTab: String get() = string(R.string.tab_insights)
    val planTab: String get() = string(R.string.tab_plan)

    // #283 wide drawer items (iPad sidebar groups).
    val recurringItem: String get() = string(R.string.recurring_title)
    val budgetsItem: String get() = string(R.string.budgets_title)
    val goalsItem: String get() = string(R.string.goals_title)

    /** Compact bottom-bar tabs (#283: Home · Activity · Plan · Insights). */
    val tabs: List<String> get() = listOf(homeTab, activityTab, planTab, insightsTab)

    /** In both shells; Plan is a compact tab only (wide splits it into drawer items). */
    private val sharedItems: List<String> get() = listOf(homeTab, activityTab, insightsTab)

    /** Content unique to one destination and independent of anything the user typed there. */
    private val markers: Map<String, SemanticsMatcher>
        get() = mapOf(
            homeTab to hasText(string(R.string.home_title)),
            activityTab to hasContentDescription(string(R.string.filters)),
            // Goals moved to Plan (#283); the spending heading is Insights-only.
            insightsTab to hasText(string(R.string.insights_spending)),
            planTab to hasTestTag(PLAN_CONTENT_TAG),
        )

    /** Any bottom-navigation item or rail item — both report `Role.Tab`. */
    val anyTab: SemanticsMatcher =
        SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)

    /** The tab item itself: the merged selectable node, not the top-bar title sharing its text. */
    fun tab(label: String): SemanticsMatcher = hasText(label) and anyTab

    fun ComposeTestRule.selectTab(label: String) {
        onNode(tab(label)).performClick()
        waitForIdle()
    }

    /**
     * Exactly the requested destination is visible, exactly one tab is selected, and no other
     * destination's content is left on screen.
     */
    fun ComposeTestRule.assertOnly(expected: String) {
        markers.forEach { (label, marker) ->
            if (label == expected) {
                onNode(marker).assertIsDisplayed()
                onNode(tab(label)).assertIsSelected()
            } else {
                onAllNodes(marker).assertCountEquals(0)
                // An item may be absent (Plan on wide); it must never be the selected one.
                onAllNodes(tab(label) and SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
                    .assertCountEquals(0)
            }
        }
        // Scoped to tab items on purpose: `Selected` is also how a Material filter chip reports
        // itself, and Home and Activity both show chips. An unscoped count would fail on those
        // rather than on anything the navigation shell did.
        onAllNodes(anyTab and SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
            .assertCountEquals(1)
    }

    /** One shell, not two: a bottom bar and a rail rendering together would double every tab. */
    fun ComposeTestRule.assertSingleShell() {
        sharedItems.forEach { onAllNodes(tab(it)).assertCountEquals(1) }
        assertTrue("Plan tab doubled", onAllNodes(tab(planTab)).fetchSemanticsNodes().size <= 1)
    }

    companion object {
        /** Mirrors `PLAN_CONTENT_TAG` in production (`features/plan/PlanScreen.kt`). */
        const val PLAN_CONTENT_TAG = "plan-content"
    }
}
