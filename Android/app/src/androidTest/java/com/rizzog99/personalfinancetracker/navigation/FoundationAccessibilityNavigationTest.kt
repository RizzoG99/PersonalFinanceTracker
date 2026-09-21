package com.rizzog99.personalfinancetracker.navigation

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.ui.components.MainTopBar
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** AC-tagged production shell evidence for #113 (`M1-A11Y-BASE`). */
@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalComposeUiApi::class)
class FoundationAccessibilityNavigationTest {

    @get:Rule
    val rule = createComposeRule()

    private data class ShellControls(
        val widthDp: MutableState<Int>,
        val locale: MutableState<Locale>,
        val fontScale: MutableState<Float>,
        val navController: NavHostController,
    )

    private fun hostShell(
        widthDp: Int = 411,
        locale: Locale = Locale.ENGLISH,
        fontScale: Float = 1f,
    ): ShellControls {
        val width = mutableStateOf(widthDp)
        val language = mutableStateOf(locale)
        val scale = mutableStateOf(fontScale)
        lateinit var navController: NavHostController
        rule.setContent {
            val base = LocalContext.current
            val inputModeManager = LocalInputModeManager.current
            LaunchedEffect(Unit) { inputModeManager.requestInputMode(InputMode.Keyboard) }
            val context = localeContext(base, language.value)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = width.value
                this.fontScale = scale.value
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, scale.value),
            ) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                    navController = rememberNavController()
                    PersonalFinanceNavHost(navController = navController)
                }
            }
        }
        rule.waitForIdle()
        return ShellControls(width, language, scale, navController)
    }

    private fun localeContext(base: Context, locale: Locale): Context {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(locale)) },
        )
        return object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    }

    private fun string(id: Int, locale: Locale): String {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        return localeContext(base, locale).getString(id)
    }

    private val anyTab = SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)

    private fun tab(label: String) = hasText(label) and anyTab

    private fun flattenedSemantics(): List<SemanticsNode> {
        fun flatten(node: SemanticsNode): List<SemanticsNode> =
            listOf(node) + node.children.flatMap(::flatten)
        return flatten(rule.onRoot(useUnmergedTree = true).fetchSemanticsNode())
    }

    private fun touchSizeDp(node: SemanticsNode): Pair<Float, Float> = with(node.layoutInfo.density) {
        node.touchBoundsInRoot.width.toDp().value to node.touchBoundsInRoot.height.toDp().value
    }

    private fun assertMinimumTarget(node: SemanticsNode, label: String) {
        val (width, height) = touchSizeDp(node)
        assertTrue("$label touch width is ${width}dp", width >= 47.5f)
        assertTrue("$label touch height is ${height}dp", height >= 47.5f)
    }

    private fun requestKeyboardFocus(matcher: SemanticsMatcher) {
        val node = rule.onNode(matcher)
        node.performSemanticsAction(SemanticsActions.RequestFocus) { it() }
        rule.waitForIdle()
        node.assertIsFocused()
    }

    private fun assertNavigationSemantics(locale: Locale, selectedLabel: String) {
        val labels = listOf(
            string(R.string.tab_home, locale),
            string(R.string.tab_activity, locale),
            string(R.string.tab_insights, locale),
        )
        val nodes = rule.onAllNodes(anyTab).fetchSemanticsNodes()
        assertEquals("exactly three primary navigation nodes", 3, nodes.size)
        assertEquals(
            "exactly one selected destination",
            1,
            nodes.count { it.config.getOrNull(SemanticsProperties.Selected) == true },
        )
        labels.forEach { label ->
            val node = rule.onNode(tab(label)).fetchSemanticsNode()
            assertEquals(listOf(label), node.config.getOrNull(SemanticsProperties.Text)?.map { it.text })
            assertEquals(label == selectedLabel, node.config.getOrNull(SemanticsProperties.Selected))
            assertEquals(Role.Tab, node.config.getOrNull(SemanticsProperties.Role))
            assertTrue(
                "$label must not repeat its visible label as a content description",
                node.config.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty(),
            )
            assertMinimumTarget(node, label)

            val descendants = flattenedSemantics().filter {
                it.id != node.id && node.boundsInRoot.contains(it.boundsInRoot.center)
            }
            assertTrue(
                "$label has a duplicate icon/child description: " +
                    descendants.mapNotNull { it.config.getOrNull(SemanticsProperties.ContentDescription) },
                descendants.none { !it.config.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty() },
            )
        }
    }

    @Test
    fun ac01_navigationKeepsLocalizedRoleSelectionAndSingleSpeechLabelAcrossShellChanges() {
        val controls = hostShell()
        val enHome = string(R.string.tab_home, Locale.ENGLISH)
        val enActivity = string(R.string.tab_activity, Locale.ENGLISH)
        assertNavigationSemantics(Locale.ENGLISH, enHome)

        rule.onNode(tab(enActivity)).performClick()
        rule.waitForIdle()
        assertNavigationSemantics(Locale.ENGLISH, enActivity)

        controls.locale.value = Locale.ITALIAN
        rule.waitForIdle()
        val itActivity = string(R.string.tab_activity, Locale.ITALIAN)
        assertNavigationSemantics(Locale.ITALIAN, itActivity)

        controls.widthDp.value = 900
        rule.waitForIdle()
        assertNavigationSemantics(Locale.ITALIAN, itActivity)
        assertEquals("activity", controls.navController.currentDestination?.route)
    }

    @Test
    fun ac02_primaryDestinationTitlesAreHeadingsExactlyOnce() {
        hostShell()
        val destinations = listOf(
            R.string.tab_home to R.string.home_title,
            R.string.tab_activity to R.string.tab_activity,
            R.string.tab_insights to R.string.tab_insights,
        )
        destinations.forEachIndexed { index, (tabRes, titleRes) ->
            val title = string(titleRes, Locale.ENGLISH)
            if (index > 0) rule.onNode(tab(string(tabRes, Locale.ENGLISH))).performClick()
            rule.waitForIdle()
            rule.onAllNodes(
                hasText(title) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading),
                useUnmergedTree = true,
            ).assertCountEquals(1)
        }
    }

    @Test
    fun ac03_themeActionUsesNativeToggleStateAndA48DpTarget() {
        val dark = mutableStateOf(false)
        rule.setContent {
            PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                MainTopBar(
                    title = "Home",
                    isDarkTheme = dark.value,
                    onToggleTheme = { dark.value = !dark.value },
                    onOpenSettings = {},
                )
            }
        }

        val toggle = rule.onNode(hasContentDescription(string(R.string.toggle_theme, Locale.ENGLISH)))
        toggle.assertHasClickAction()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ToggleableState, ToggleableState.Off))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Role))
        assertMinimumTarget(toggle.fetchSemanticsNode(), "theme toggle")

        toggle.performClick()
        rule.waitForIdle()
        toggle.assert(SemanticsMatcher.expectValue(SemanticsProperties.ToggleableState, ToggleableState.On))
        assertTrue(dark.value)
    }

    @Test
    @OptIn(ExperimentalTestApi::class)
    fun ac04_realDirectionalKeysFollowTheCompactBarAndWideRail() {
        val controls = hostShell()
        val markers = NavShellMarkers(Locale.ENGLISH)

        requestKeyboardFocus(tab(markers.homeTab))
        rule.onRoot().performKeyInput { pressKey(Key.DirectionRight) }
        rule.onNode(tab(markers.activityTab)).assertIsFocused()
        rule.onRoot().performKeyInput { pressKey(Key.DirectionRight) }
        rule.onNode(tab(markers.insightsTab)).assertIsFocused()

        controls.widthDp.value = 900
        rule.waitForIdle()
        requestKeyboardFocus(tab(markers.homeTab))
        rule.onRoot().performKeyInput { pressKey(Key.DirectionDown) }
        rule.onNode(tab(markers.activityTab)).assertIsFocused()
        rule.onRoot().performKeyInput { pressKey(Key.DirectionDown) }
        rule.onNode(tab(markers.insightsTab)).assertIsFocused()
    }

    @Test
    fun ac05_navigationAndCompactIconActionsMeetThe48DpStandard() {
        val controls = hostShell()
        assertNavigationSemantics(Locale.ENGLISH, string(R.string.tab_home, Locale.ENGLISH))
        listOf(R.string.add_transaction, R.string.toggle_theme, R.string.settings_title).forEach { id ->
            val label = string(id, Locale.ENGLISH)
            val node = rule.onNode(hasContentDescription(label)).fetchSemanticsNode()
            assertMinimumTarget(node, label)
        }

        controls.widthDp.value = 900
        rule.waitForIdle()
        assertNavigationSemantics(Locale.ENGLISH, string(R.string.tab_home, Locale.ENGLISH))
        assertMinimumTarget(
            rule.onNode(hasContentDescription(string(R.string.add_transaction, Locale.ENGLISH)))
                .fetchSemanticsNode(),
            "wide add transaction",
        )
    }

    @Test
    fun ac06_destinationLabelsStaySingleLineContainedAndSeparatedAt200Percent() {
        val controls = hostShell(fontScale = 2f)
        val combinations = listOf(
            Locale.ENGLISH to 411,
            Locale.ITALIAN to 411,
            Locale.ENGLISH to 900,
            Locale.ITALIAN to 900,
        )
        combinations.forEach { (locale, width) ->
            controls.locale.value = locale
            controls.widthDp.value = width
            rule.waitForIdle()
            val labels = listOf(
                string(R.string.tab_home, locale),
                string(R.string.tab_activity, locale),
                string(R.string.tab_insights, locale),
            )
            val tabNodes = labels.map { rule.onNode(tab(it)).fetchSemanticsNode() }
            labels.zip(tabNodes).forEach { (label, tabNode) ->
                val candidates = flattenedSemantics().filter { node ->
                    node.config.getOrNull(SemanticsProperties.Text)?.singleOrNull()?.text == label &&
                        tabNode.boundsInRoot.contains(node.boundsInRoot.center) &&
                        node.config.getOrNull(SemanticsActions.GetTextLayoutResult) != null
                }
                assertEquals("$label must expose one label layout inside its navigation item", 1, candidates.size)
                val results = mutableListOf<TextLayoutResult>()
                val readLayout = candidates.single().config[SemanticsActions.GetTextLayoutResult].action
                assertTrue("$label must expose a text-layout action", readLayout?.invoke(results) == true)
                val layout = results.single()
                assertEquals("$label wrapped at width=$width locale=$locale", 1, layout.lineCount)
                assertEquals(
                    "$label lost visible characters at width=$width locale=$locale",
                    label.length,
                    layout.getLineEnd(0, visibleEnd = true),
                )
                assertTrue("$label moved above its navigation item", candidates.single().boundsInRoot.top >= tabNode.boundsInRoot.top)
                assertTrue("$label moved below its navigation item", candidates.single().boundsInRoot.bottom <= tabNode.boundsInRoot.bottom)
                assertMinimumTarget(tabNode, "$label at 200%")
            }

            val sorted = if (width < 840) tabNodes.sortedBy { it.boundsInRoot.left } else tabNodes.sortedBy { it.boundsInRoot.top }
            sorted.zipWithNext().forEach { (first, second) ->
                assertFalse(
                    "navigation targets overlap at width=$width locale=$locale: ${first.boundsInRoot} / ${second.boundsInRoot}",
                    first.boundsInRoot.overlaps(second.boundsInRoot),
                )
            }
        }
    }
}
