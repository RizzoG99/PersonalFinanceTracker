package com.rizzog99.personalfinancetracker.navigation

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.performTextInput
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Parity `M1-NAV-SHELL` (#110): route identity read from the **actual back queue**, plus the two
 * things a fixed-size emulator screen cannot show — the wide (rail) branch and Italian labels.
 *
 * This hosts the production [PersonalFinanceNavHost] and passes it a controller the test owns. That
 * one parameter is the whole seam: there is no second graph here that could drift away from the one
 * that ships. `screenWidthDp` and the locale are overridden through the composition locals the shell
 * already reads, so the production branch logic is the thing under test, not a copy of it.
 */
@RunWith(AndroidJUnit4::class)
class NavShellGraphTest {

    @get:Rule
    val rule = createComposeRule()

    private fun routes(navController: NavHostController): List<String> =
        navController.currentBackStack.value.mapNotNull { it.destination.route }

    /**
     * Hosts the production graph. [widthDp] drives the adaptive branch, [locale] the labels, and the
     * returned width state lets a test move across the breakpoint inside one composition.
     */
    private fun host(
        widthDp: Int = 411,
        locale: Locale? = null,
    ): Pair<NavHostController, MutableState<Int>> {
        lateinit var navController: NavHostController
        val width = mutableStateOf(widthDp)
        rule.setContent {
            val context = localeContext(LocalContext.current, locale)
            val configuration = Configuration(context.resources.configuration)
                .apply { screenWidthDp = width.value }
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
            ) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                    navController = rememberNavController()
                    PersonalFinanceNavHost(navController = navController)
                }
            }
        }
        rule.waitForIdle()
        return navController to width
    }

    /**
     * Italian resources over the *same* context chain.
     *
     * A bare `createConfigurationContext` would be wrong here even though it returns Italian
     * strings: `LocalActivityResultRegistryOwner` resolves by walking `LocalContext`'s
     * `ContextWrapper` chain for the Activity, and a fresh configuration context is not on it — so
     * Home's photo-picker launcher throws `No ActivityResultRegistryOwner was provided` before a
     * single label can be read. Wrapping keeps the Activity reachable and swaps only the resources.
     */
    private fun localeContext(base: Context, locale: Locale?): Context = locale?.let {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(it)) },
        )
        object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    } ?: base

    private fun typeInActivitySearch(text: String) {
        rule.onAllNodes(hasSetTextAction()).assertCountEquals(1)
        rule.onNode(hasSetTextAction()).performTextInput(text)
        rule.waitForIdle()
    }

    // --- AC-01 initial destination -------------------------------------------------------

    @Test
    fun ac01_startDestinationIsHomeAndTheQueueHoldsOnlyIt(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host()
        assertEquals("home", nav.graph.startDestinationRoute)
        assertEquals(listOf("home"), routes(nav))
        rule.assertOnly(homeTab)
    }

    // --- AC-02 destination selection -----------------------------------------------------

    @Test
    fun ac02_selectionMapsOntoTheRouteItClaims(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host()
        listOf(activityTab to "activity", insightsTab to "insights", homeTab to "home")
            .forEach { (label, route) ->
                rule.selectTab(label)
                assertEquals(route, nav.currentDestination?.route)
                rule.assertOnly(label)
            }
    }

    // --- AC-03 repeated selection --------------------------------------------------------

    /**
     * Two claims, and they need two different assertions.
     *
     * Queue length catches a duplicate *push*. It does not catch the other failure: dropping the
     * `currentRoute != destination.route` guard makes a re-selection `popUpTo(home)` the live entry
     * and push a fresh one — same length, new `NavBackStackEntry`, and the `ActivityViewModel` scoped
     * to it is destroyed with the old one. The search text is what notices.
     */
    @Test
    fun ac03_reselectingAddsNoEntryAndKeepsDestinationState(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host()
        rule.selectTab(activityTab)
        assertEquals(listOf("home", "activity"), routes(nav))
        val entry = nav.currentBackStackEntry

        typeInActivitySearch("coffee")
        repeat(3) { rule.selectTab(activityTab) }

        assertEquals(listOf("home", "activity"), routes(nav))
        assertTrue(
            "re-selection recreated the back-stack entry, which destroys the destination's ViewModel",
            entry === nav.currentBackStackEntry,
        )
        rule.onNode(hasSetTextAction()).assert(hasText("coffee"))
        rule.assertOnly(activityTab)
    }

    @Test
    fun ac03_reselectingTheStartDestinationAddsNoEntry(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host()
        repeat(3) { rule.selectTab(homeTab) }
        assertEquals(listOf("home"), routes(nav))
        rule.assertOnly(homeTab)
    }

    // --- AC-05 destination state across a peer round trip --------------------------------

    /**
     * `saveState` / `restoreState` on the primary navigation options are what make a tab round trip
     * feel like returning rather than starting over. Without them the Activity entry is popped and
     * rebuilt, and the search text goes with it — a loss that no route or selection assertion can
     * see, because the route and the selection are both exactly right.
     */
    @Test
    fun ac05_leavingAndReturningToAPeerRestoresItsState(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host()
        rule.selectTab(activityTab)
        typeInActivitySearch("coffee")

        rule.selectTab(insightsTab)
        rule.assertOnly(insightsTab)
        rule.selectTab(activityTab)

        rule.assertOnly(activityTab)
        assertEquals(listOf("home", "activity"), routes(nav))
        rule.onNode(hasSetTextAction()).assert(hasText("coffee"))
    }

    // --- AC-04 system Back ---------------------------------------------------------------

    @Test
    fun ac04_backQueueNeverGrowsPastTwoEntriesAndBackReturnsToHome(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host()
        listOf(activityTab, insightsTab, activityTab, homeTab, insightsTab).forEach {
            rule.selectTab(it)
            val queue = routes(nav)
            assertTrue("queue grew past the documented [home] / [home, X] shape: $queue", queue.size <= 2)
            assertEquals("home", queue.first())
        }
        Espresso.pressBack()
        rule.waitForIdle()
        assertEquals(listOf("home"), routes(nav))
        rule.assertOnly(homeTab)
    }

    // --- AC-06 localized labels ----------------------------------------------------------

    @Test
    fun ac06_italianLabelsIdentifyAllThreeDestinations() {
        val italian = NavShellMarkers(Locale.ITALIAN)
        host(locale = Locale.ITALIAN)
        with(italian) {
            assertEquals(listOf("Home", "Attività", "Analisi"), tabs)
            tabs.forEach { rule.onNode(tab(it)).assertIsDisplayed() }
            rule.selectTab(activityTab)
            rule.assertOnly(activityTab)
        }
    }

    // --- AC-07 wide layout ---------------------------------------------------------------

    @Test
    fun ac07_wideLayoutKeepsTheSameRouteSelectionAndBackContract(): Unit = with(NavShellMarkers()) {
        val (nav, _) = host(widthDp = 900)
        rule.assertOnly(homeTab)
        rule.assertSingleShell()

        rule.selectTab(insightsTab)
        assertEquals("insights", nav.currentDestination?.route)
        assertEquals(listOf("home", "insights"), routes(nav))
        rule.assertOnly(insightsTab)

        Espresso.pressBack()
        rule.waitForIdle()
        assertEquals(listOf("home"), routes(nav))
        rule.assertOnly(homeTab)
    }

    /**
     * 840dp is the breakpoint the shell documents, and the two shells have to actually swap there —
     * not merely both be absent or both be present.
     *
     * A rail and a bottom bar are indistinguishable by semantics: both report `Role.Tab`, the same
     * labels, and the same selected state. Geometry is what separates them. The rail stacks its
     * items down the leading edge, so Home sits *above* Activity; the bottom bar lays them out in a
     * row, so Home sits *left of* Activity at the same height. That is the assertion a shell stuck
     * on one branch fails.
     */
    @Test
    fun ac07_theRailReplacesTheBottomBarAtTheBreakpoint(): Unit = with(NavShellMarkers()) {
        val (_, width) = host(widthDp = 839)
        rule.assertSingleShell()
        var home = rule.onNode(tab(homeTab)).fetchSemanticsNode().boundsInRoot
        var activity = rule.onNode(tab(activityTab)).fetchSemanticsNode().boundsInRoot
        assertTrue(
            "below 840dp the items must sit in a row (bottom bar), got home=$home activity=$activity",
            home.left < activity.left && home.top == activity.top,
        )

        width.value = 840
        rule.waitForIdle()
        rule.assertSingleShell()
        home = rule.onNode(tab(homeTab)).fetchSemanticsNode().boundsInRoot
        activity = rule.onNode(tab(activityTab)).fetchSemanticsNode().boundsInRoot
        assertTrue(
            "at 840dp the items must stack in a column (rail), got home=$home activity=$activity",
            home.top < activity.top && home.left == activity.left,
        )
    }

    @Test
    fun ac07_crossingTheBreakpointPreservesTheSelectedDestination(): Unit = with(NavShellMarkers()) {
        val (nav, width) = host(widthDp = 411)
        rule.selectTab(activityTab)
        typeInActivitySearch("coffee")
        val entry = nav.currentBackStackEntry

        width.value = 900
        rule.waitForIdle()
        rule.assertOnly(activityTab)
        rule.assertSingleShell()
        assertEquals(listOf("home", "activity"), routes(nav))

        width.value = 411
        rule.waitForIdle()
        rule.assertOnly(activityTab)
        rule.assertSingleShell()
        assertEquals(listOf("home", "activity"), routes(nav))
        assertTrue("crossing the breakpoint must not recreate the entry", entry === nav.currentBackStackEntry)
        rule.onNode(hasSetTextAction()).assert(hasText("coffee"))
    }
}
