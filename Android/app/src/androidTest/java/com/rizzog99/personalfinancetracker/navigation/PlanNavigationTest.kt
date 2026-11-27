package com.rizzog99.personalfinancetracker.navigation

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #283 (`DRIFT-2026-10-PLAN`): the Plan tab and the iPad-like wide grouping, on the production graph
 * with the app's real store. Frozen iOS: `PlanView.swift`, `IPadSection.swift` at b649dff.
 */
@RunWith(AndroidJUnit4::class)
class PlanNavigationTest {

    @get:Rule
    val rule = createComposeRule()

    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
    private val zone = ZoneId.systemDefault()
    private lateinit var expense: FinanceCategory

    @Before
    fun setUp() = runBlocking {
        app.database.clearAllTables()
        app.categoryRepository.seedDefaultsIfEmpty()
        expense = app.categoryRepository.observeAll().first().first { it.type == TransactionType.EXPENSE }
    }

    private fun string(id: Int, locale: Locale = Locale.ENGLISH): String {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        return base.createConfigurationContext(Configuration(base.resources.configuration).apply { setLocales(android.os.LocaleList(locale)) })
            .getString(id)
    }

    /** Drives the shell's breakpoint inside one composition (`width.value = …`). */
    private val width = androidx.compose.runtime.mutableStateOf(411)

    private fun host(widthDp: Int = 411, locale: Locale? = null): NavHostController {
        lateinit var navController: NavHostController
        width.value = widthDp
        rule.setContent {
            val base = LocalContext.current
            val context = locale?.let { localized(base, it) } ?: base
            val configuration = Configuration(context.resources.configuration).apply { screenWidthDp = width.value }
            CompositionLocalProvider(LocalContext provides context, LocalConfiguration provides configuration) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                    navController = rememberNavController()
                    PersonalFinanceNavHost(navController = navController)
                }
            }
        }
        rule.waitForIdle()
        return navController
    }

    private fun localized(base: Context, locale: Locale): Context {
        val resources = base.createConfigurationContext(
            Configuration(base.resources.configuration).apply { setLocales(android.os.LocaleList(locale)) },
        ).resources
        return object : ContextWrapper(base) {
            override fun getResources(): Resources = resources
        }
    }

    private fun waitFor(matcher: SemanticsMatcher) =
        rule.waitUntil(20_000) { rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    private val anyTab = SemanticsMatcher.expectValue(SemanticsProperties.Role, androidx.compose.ui.semantics.Role.Tab)
    private fun tab(label: String) = hasText(label) and anyTab
    private val heading = SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)
    private fun baseRoute(nav: NavHostController) = nav.currentDestination?.route?.substringBefore('?')

    private fun selectPlan() {
        rule.onNode(tab(string(R.string.tab_plan))).performClick()
        waitFor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG))
    }

    private fun rule(note: String, amount: String, startInDays: Long, frequency: RecurrenceFrequency = RecurrenceFrequency.MONTHLY): RecurrenceRule =
        runBlocking {
            app.recurrenceRepository.create(
                NewRecurrenceRule(
                    frequency = frequency, interval = 1,
                    startDate = LocalDate.now(zone).plusDays(startInDays).atTime(10, 0).atZone(zone).toInstant(),
                    amount = BigDecimal(amount), note = note, categoryLabel = expense.name, categoryId = expense.id,
                    currencyCode = "EUR",
                ),
            )
        }

    private fun budget(limit: String) = runBlocking { app.categoryRepository.update(expense.copy(monthlyBudget = BigDecimal(limit))) }
    private fun goal(name: String) = runBlocking { app.goalRepository.add(NewGoal(name = name, targetAmount = BigDecimal("1000"))) }

    // --- AC-01 four tabs, Plan groups Coming up → Budgets → Goals -------------------------

    private fun phoneTabLabels(locale: Locale): List<String> {
        host(locale = locale)
        return rule.onAllNodes(anyTab).fetchSemanticsNodes()
            .sortedBy { it.boundsInRoot.left }
            .map { node -> node.config[SemanticsProperties.Text].joinToString { it.text } }
    }

    @Test
    fun ac01_phoneShowsFourTabsInOrder() =
        assertEquals(listOf("Home", "Activity", "Plan", "Insights"), phoneTabLabels(Locale.ENGLISH))

    @Test
    fun ac01_phoneShowsFourTabsInOrderInItalian() =
        assertEquals(listOf("Home", "Attività", "Pianifica", "Analisi"), phoneTabLabels(Locale.ITALIAN))

    @Test
    fun ac01_planGroupsComingUpBudgetsAndGoals() {
        rule("Netflix", "-13.00", startInDays = 3)
        budget("200")
        goal("Holiday")
        host()
        selectPlan()

        listOf(R.string.plan_coming_up, R.string.budgets_title, R.string.goals_title).forEach {
            waitFor(hasText(string(it)) and heading and hasAnyAncestor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG)))
        }
        val tops = listOf(R.string.plan_coming_up, R.string.budgets_title, R.string.goals_title).map {
            rule.onNode(hasText(string(it)) and heading and hasAnyAncestor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG)))
                .fetchSemanticsNode().boundsInRoot.top
        }
        assertEquals("sections in iOS order", tops.sorted(), tops)
        rule.onNode(hasText("Netflix") and hasClickAction()).performScrollTo().assertIsDisplayed()
        rule.onNode(hasText(expense.name)).performScrollTo().assertIsDisplayed()
        rule.onNode(hasText("Holiday")).performScrollTo().assertIsDisplayed()
        rule.onNode(tab(string(R.string.tab_plan))).assertIsSelected()
    }

    // --- AC-02 See all / row → recurring; Manage → Budgets -------------------------------

    @Test
    fun ac02_seeAllOpensRecurringAndARowOpensThatRulesEditor() {
        rule("Gym", "-30.00", startInDays = 5)
        rule("Netflix", "-13.00", startInDays = 3)
        val nav = host()
        selectPlan()

        rule.onNode(hasText(string(R.string.plan_see_all))).performScrollTo().performClick()
        waitFor(hasText(string(R.string.recurring_title)) and heading)
        assertEquals("recurring", baseRoute(nav))
        Espresso.pressBack()
        waitFor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG))
        assertEquals("plan", baseRoute(nav))

        rule.onNode(hasText("Netflix") and hasClickAction()).performScrollTo().performClick()
        waitFor(hasText(string(R.string.edit_recurring)))
        rule.onNode(hasSetTextAction() and hasText("Netflix")).assertExists()
        rule.onNode(hasSetTextAction() and hasText("Gym")).assertDoesNotExist()
    }

    // --- AC-03 empty states ---------------------------------------------------------------

    @Test
    fun ac03_allEmptyShowsWelcomeAndItsAddRecurringOpensTheEditor() {
        host()
        selectPlan()
        waitFor(hasText(string(R.string.plan_welcome_title)))
        listOf(R.string.plan_add_recurring, R.string.plan_create_budget, R.string.add_goal).forEach {
            rule.onNode(hasText(string(it)) and hasClickAction()).assertExists()
        }
        rule.onNode(hasText(string(R.string.plan_add_recurring)) and hasClickAction()).performScrollTo().performClick()
        waitFor(hasText(string(R.string.recurring_title)) and heading)
        // The add editor is open with Repeat on (iOS `presetRecurring: true`).
        waitFor(hasText(string(R.string.repeat_transaction)))
    }

    @Test
    fun ac03_welcomeCreateBudgetOpensBudgetsAndAddGoalOpensTheGoalEditor() {
        val nav = host()
        selectPlan()
        waitFor(hasText(string(R.string.plan_welcome_title)))
        rule.onNode(hasText(string(R.string.plan_create_budget)) and hasClickAction()).performScrollTo().performClick()
        waitFor(hasText(string(R.string.budgets_title)) and heading)
        assertEquals("budgets", baseRoute(nav))
        Espresso.pressBack()
        waitFor(hasText(string(R.string.plan_welcome_title)))

        rule.onNode(hasText(string(R.string.add_goal)) and hasClickAction()).performScrollTo().performClick()
        waitFor(hasContentDescription(string(R.string.add_goal)))
    }

    @Test
    fun ac03_sectionEmptyLinesWhenOnlySomePartsExist() {
        rule("Annual fee", "-50.00", startInDays = 30) // active, but outside the 14-day window
        host()
        selectPlan()
        waitFor(hasText(string(R.string.plan_nothing_due)))
        rule.onNode(hasText(string(R.string.plan_no_budgets))).performScrollTo().assertIsDisplayed()
        rule.onNode(hasText(string(R.string.plan_create_budget)) and hasClickAction()).assertExists()
        rule.onNode(hasText(string(R.string.set_first_goal))).performScrollTo().assertIsDisplayed()
        rule.onAllNodes(hasText(string(R.string.plan_welcome_title))).fetchSemanticsNodes().let { assertEquals(0, it.size) }
    }

    @Test
    fun ac03_noActiveRulesShowsTheRecurringEmptyLine() {
        budget("200")
        host()
        selectPlan()
        waitFor(hasText(string(R.string.plan_no_recurring)))
        rule.onNode(hasText(string(R.string.plan_add_recurring)) and hasClickAction()).assertExists()
    }

    // --- AC-04 Budgets left Settings; Manage round trip -----------------------------------

    @Test
    fun ac04_settingsHasNoBudgetsAndManageRoundTripsThroughPlan() {
        budget("200")
        val nav = host()
        rule.onNode(hasContentDescription(string(R.string.settings_title))).performClick()
        waitFor(hasText(string(R.string.settings_title)))
        rule.onAllNodes(hasText(string(R.string.budgets_title))).fetchSemanticsNodes().let { assertEquals("Budgets row in Settings", 0, it.size) }
        Espresso.pressBack()
        rule.waitForIdle()

        selectPlan()
        rule.onNode(hasText(string(R.string.plan_manage)) and hasClickAction()).performScrollTo().performClick()
        waitFor(hasText(string(R.string.budgets_title)) and heading)
        assertEquals("budgets", baseRoute(nav))
        Espresso.pressBack()
        waitFor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG))
        rule.onNode(tab(string(R.string.tab_plan))).assertIsSelected()
    }

    // --- AC-05 wide grouping (iPad sidebar) ------------------------------------------------

    @Test
    fun ac05_wideDrawerMirrorsTheIpadGroups() {
        goal("Holiday")
        val nav = host(widthDp = 1280)
        val drawer = hasAnyAncestor(hasTestTag("nav-drawer"))
        listOf(R.string.tab_plan, R.string.tab_insights).forEach {
            rule.onNode(hasText(string(it)) and heading and drawer).assertExists()
        }
        val items = rule.onAllNodes(anyTab).fetchSemanticsNodes().sortedBy { it.boundsInRoot.top }
            .map { node -> node.config[SemanticsProperties.Text].joinToString { it.text } }
        assertEquals(
            listOf(R.string.tab_home, R.string.tab_activity, R.string.recurring_title, R.string.budgets_title, R.string.goals_title, R.string.tab_insights, R.string.settings_title)
                .map { string(it) },
            items,
        )

        listOf(
            R.string.budgets_title to "budgets",
            R.string.goals_title to "goals",
            R.string.recurring_title to "recurring",
        ).forEach { (label, route) ->
            rule.onNode(tab(string(label))).performClick()
            rule.waitForIdle()
            assertEquals(route, baseRoute(nav))
            rule.onNode(tab(string(label))).assertIsSelected()
            // A drawer root, like an iPad sidebar destination: no back arrow (D-05).
            rule.onAllNodes(hasContentDescription(string(R.string.back))).fetchSemanticsNodes().let { assertEquals(0, it.size) }
        }
        rule.onNode(hasText("Holiday")).assertDoesNotExist()
        rule.onNode(tab(string(R.string.goals_title))).performClick()
        waitFor(hasText("Holiday"))
    }

    @Test
    fun ac05_crossingTheBreakpointOnPlanFamilyScreensKeepsNavigation() {
        goal("Holiday")
        val nav = host(widthDp = 1280)
        rule.onNode(tab(string(R.string.goals_title))).performClick()
        waitFor(hasText("Holiday"))

        // Wide-only Goals on a narrowed window: still the bottom bar, under Plan.
        width.value = 411
        rule.waitForIdle()
        assertEquals("goals", baseRoute(nav))
        rule.onNode(tab(string(R.string.tab_plan))).assertIsSelected()
        rule.onNode(tab(string(R.string.tab_plan))).performClick()
        waitFor(hasTestTag(NavShellMarkers.PLAN_CONTENT_TAG))

        // Plan on a widened window keeps the drawer, every item still reachable (D-10).
        width.value = 1280
        rule.waitForIdle()
        rule.onNode(hasTestTag("nav-drawer")).assertExists()
        rule.onNode(tab(string(R.string.budgets_title))).performClick()
        rule.waitForIdle()
        assertEquals("budgets", baseRoute(nav))
    }

    // --- AC-06 Insights no longer shows goals ---------------------------------------------

    @Test
    fun ac06_insightsNoLongerShowsGoals() {
        goal("Holiday")
        host()
        rule.onNode(tab(string(R.string.tab_insights))).performClick()
        waitFor(hasText(string(R.string.explorer_breakdown)))
        rule.onNode(hasText(string(R.string.goals_title))).assertDoesNotExist()
        rule.onNode(hasText("Holiday")).assertDoesNotExist()
        rule.onNode(hasText(string(R.string.new_goal))).assertDoesNotExist()
    }
}
