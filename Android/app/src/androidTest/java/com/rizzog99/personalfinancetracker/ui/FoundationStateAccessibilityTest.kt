package com.rizzog99.personalfinancetracker.ui

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.FoundationStartupLoadingState
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ActivityContent
import com.rizzog99.personalfinancetracker.features.activity.ActivityUiState
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsContent
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsUiState
import com.rizzog99.personalfinancetracker.ui.components.EmptyState
import com.rizzog99.personalfinancetracker.ui.components.ErrorState
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.components.StoredDataUnavailableState
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** AC-tagged shared-state and production-consumer evidence for #113. */
@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalComposeUiApi::class)
class FoundationStateAccessibilityTest {

    private enum class TransitionPhase { ERROR, LOADING, RECOVERED }

    @get:Rule
    val rule = createComposeRule()

    private fun host(
        locale: Locale = Locale.ENGLISH,
        widthDp: Int = 411,
        fontScale: Float = 1f,
        theme: ThemeMode = ThemeMode.LIGHT,
        content: @Composable () -> Unit,
    ) {
        rule.setContent {
            val base = LocalContext.current
            val inputModeManager = LocalInputModeManager.current
            LaunchedEffect(Unit) { inputModeManager.requestInputMode(InputMode.Keyboard) }
            val context = localeContext(base, locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = widthDp
                this.fontScale = fontScale
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, fontScale),
            ) {
                PersonalFinanceTheme(themeMode = theme) {
                    Surface(modifier = Modifier.fillMaxSize()) { content() }
                }
            }
        }
        rule.waitForIdle()
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

    private fun string(id: Int, locale: Locale = Locale.ENGLISH): String {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        return localeContext(base, locale).getString(id)
    }

    private fun flattenedSemantics(): List<SemanticsNode> {
        fun flatten(node: SemanticsNode): List<SemanticsNode> =
            listOf(node) + node.children.flatMap(::flatten)
        return flatten(rule.onRoot(useUnmergedTree = true).fetchSemanticsNode())
    }

    private fun assertSingleLiveText(label: String, mode: LiveRegionMode) {
        val liveNodes = flattenedSemantics().filter {
            it.config.getOrNull(SemanticsProperties.LiveRegion) != null
        }
        assertEquals("one stable live region for $label", 1, liveNodes.size)
        assertEquals(mode, liveNodes.single().config.getOrNull(SemanticsProperties.LiveRegion))
        assertEquals(
            listOf(label),
            liveNodes.single().config.getOrNull(SemanticsProperties.Text)?.map { it.text },
        )
    }

    private fun assertMinimumTarget(node: SemanticsNode, label: String) = with(node.layoutInfo.density) {
        val width = node.touchBoundsInRoot.width.toDp().value
        val height = node.touchBoundsInRoot.height.toDp().value
        assertTrue("$label touch width is ${width}dp", width >= 47.5f)
        assertTrue("$label touch height is ${height}dp", height >= 47.5f)
    }

    private fun requestKeyboardFocus(matcher: SemanticsMatcher) {
        var accepted = false
        rule.onNode(matcher).performSemanticsAction(SemanticsActions.RequestFocus) {
            accepted = it()
        }
        rule.waitForIdle()
        assertTrue("focus request was rejected for $matcher", accepted)
        rule.onNode(matcher).assertIsFocused()
    }

    @Test
    fun ac02_startupDatabaseStatusIsLocalizedProgressAndAStableLiveRegion() {
        val message = string(R.string.startup_loading_data)
        host { FoundationStartupLoadingState(message) }

        rule.onNodeWithText(message).assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.ProgressBarRangeInfo,
                ProgressBarRangeInfo.Indeterminate,
            ),
        ).assertIsDisplayed()
        assertSingleLiveText(message, LiveRegionMode.Polite)
    }

    @Test
    fun ac02_startupSecurityStatusIsItalianAndKeepsOneStableAnnouncement() {
        val message = string(R.string.startup_loading_security, Locale.ITALIAN)
        host(locale = Locale.ITALIAN) { FoundationStartupLoadingState(message) }

        rule.onNodeWithText("Verifica della sicurezza dell’app").assertIsDisplayed()
        assertSingleLiveText(message, LiveRegionMode.Polite)
    }

    @Test
    fun ac02_categoryProductionLoadingBranchUsesSpecificProgressSemanticsAt200Percent() {
        val message = string(R.string.category_loading, Locale.ITALIAN)
        host(locale = Locale.ITALIAN, widthDp = 411, fontScale = 2f) {
            CategorySettingsContent(
                state = CategorySettingsUiState(isLoading = true),
                onAdd = {},
                onEdit = {},
                modifier = Modifier.fillMaxSize(),
            )
        }

        rule.onNodeWithText(message).performScrollTo().assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.ProgressBarRangeInfo,
                ProgressBarRangeInfo.Indeterminate,
            ),
        ).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.loading, Locale.ITALIAN)).assertDoesNotExist()
        assertSingleLiveText(message, LiveRegionMode.Polite)
    }

    @Test
    fun ac02_headingExplanationAndActionFollowVisualTaskOrder() {
        val title = string(R.string.error_state_title)
        val message = string(R.string.error_state_message)
        val retry = string(R.string.retry)
        host(fontScale = 2f) { ErrorState(message = message, onRetry = {}) }

        val heading = rule.onNodeWithText(title).fetchSemanticsNode()
        val explanation = rule.onNodeWithText(message).fetchSemanticsNode()
        val action = rule.onNodeWithText(retry).fetchSemanticsNode()
        assertTrue(heading.config.contains(SemanticsProperties.Heading))
        assertTrue("heading must precede explanation", heading.boundsInRoot.top < explanation.boundsInRoot.top)
        assertTrue("explanation must precede action", explanation.boundsInRoot.top < action.boundsInRoot.top)
        assertEquals(Role.Button, action.config.getOrNull(SemanticsProperties.Role))
        assertSingleLiveText(message, LiveRegionMode.Polite)
    }

    @Test
    fun ac02_startupRecoveryReadsHeadingThenExplanationThenReassuranceWithoutFakeRetry() {
        val title = string(R.string.stored_data_unavailable_title)
        val explanation = string(R.string.stored_data_unavailable_database)
        val reassurance = string(R.string.stored_data_unavailable_reassurance)
        host(fontScale = 2f) { StoredDataUnavailableState(message = explanation) }

        val heading = rule.onNodeWithText(title).fetchSemanticsNode()
        val body = rule.onNodeWithText(explanation).fetchSemanticsNode()
        val final = rule.onNodeWithText(reassurance).fetchSemanticsNode()
        assertTrue(heading.config.contains(SemanticsProperties.Heading))
        assertTrue(heading.boundsInRoot.top < body.boundsInRoot.top)
        assertTrue(body.boundsInRoot.top < final.boundsInRoot.top)
        rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.OnClick)).assertCountEquals(0)
    }

    @Test
    fun ac03_accessibilityRetryActivatesOnceThenLeavesNoStaleOrFocusedAction() {
        val phase = mutableStateOf(TransitionPhase.ERROR)
        var retries = 0
        rule.setContent {
            val inputModeManager = LocalInputModeManager.current
            LaunchedEffect(Unit) { inputModeManager.requestInputMode(InputMode.Keyboard) }
            PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                when (phase.value) {
                    TransitionPhase.ERROR -> ErrorState(
                        message = string(R.string.error_state_message),
                        onRetry = {
                            retries++
                            phase.value = TransitionPhase.LOADING
                        },
                        modifier = Modifier.fillMaxSize(),
                    )
                    TransitionPhase.LOADING -> LoadingState(modifier = Modifier.fillMaxSize())
                    TransitionPhase.RECOVERED -> EmptyState(
                        title = string(R.string.empty_state_title),
                        message = string(R.string.empty_state_message),
                        action = { Button(onClick = {}) { Text(string(R.string.add_transaction)) } },
                    )
                }
            }
        }

        val retry = rule.onNodeWithText(string(R.string.retry))
        requestKeyboardFocus(hasText(string(R.string.retry)))
        retry.performSemanticsAction(SemanticsActions.OnClick) { it() }
        rule.waitForIdle()
        assertEquals(1, retries)
        retry.assertDoesNotExist()
        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.ProgressBarRangeInfo,
                ProgressBarRangeInfo.Indeterminate,
            ),
        ).assertIsDisplayed()

        phase.value = TransitionPhase.RECOVERED
        rule.waitForIdle()
        rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo))
            .assertCountEquals(0)
        requestKeyboardFocus(hasText(string(R.string.add_transaction)))
    }

    @Test
    fun ac03_productionFirstItemClearFilterAndDismissActionsAreButtonsAndActivateOnce() {
        var activations = 0
        host {
            ActivityContent(
                state = ActivityUiState(isLoading = false),
                error = R.string.activity_update_failed,
                onSearchChange = {},
                onTypeFilterChange = {},
                onClearError = { activations++ },
                onClearSearchAndFilters = { activations++ },
                onRetry = { activations++ },
                onAdd = { activations++ },
                onEdit = {},
                onDelete = {},
                modifier = Modifier.fillMaxSize(),
            )
        }

        listOf(R.string.dismiss, R.string.add_transaction).forEach { id ->
            val node = rule.onNodeWithText(string(id)).fetchSemanticsNode()
            assertEquals(Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            assertMinimumTarget(node, string(id))
        }
        rule.onNodeWithText(string(R.string.dismiss))
            .performSemanticsAction(SemanticsActions.OnClick) { it() }
        rule.onNodeWithText(string(R.string.add_transaction))
            .performSemanticsAction(SemanticsActions.OnClick) { it() }
        assertEquals(2, activations)
    }

    @Test
    fun ac03_noResultsClearActionIsReachableAndRestoresMeaningfulContent() {
        val state = mutableStateOf(
            ActivityUiState(
                isLoading = false,
                allTransactions = listOf(transaction()),
                visibleTransactions = emptyList(),
                searchText = "missing",
            ),
        )
        rule.setContent {
            PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                ActivityContent(
                    state = state.value,
                    error = null,
                    onSearchChange = {},
                    onTypeFilterChange = {},
                    onClearError = {},
                    onClearSearchAndFilters = {
                        state.value = state.value.copy(
                            visibleTransactions = state.value.allTransactions,
                            searchText = "",
                        )
                    },
                    onRetry = {},
                    onAdd = {},
                    onEdit = {},
                    onDelete = {},
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        val clear = rule.onNodeWithText(string(R.string.clear_search_and_filters))
        clear.performScrollTo().assertIsDisplayed().assertHasClickAction()
        assertMinimumTarget(clear.fetchSemanticsNode(), "clear search and filters")
        clear.performSemanticsAction(SemanticsActions.OnClick) { it() }
        rule.waitForIdle()
        clear.assertDoesNotExist()
        rule.onNodeWithText("coffee").assertIsDisplayed()
    }

    @Test
    fun ac05_meaningfulStateTextHasNonZeroBoundsAndActionsMeet48DpAt200Percent() {
        host(locale = Locale.ITALIAN, widthDp = 900, fontScale = 2f, theme = ThemeMode.DARK) {
            ErrorState(
                message = string(R.string.error_state_message, Locale.ITALIAN),
                onRetry = {},
                modifier = Modifier.fillMaxSize(),
            )
        }

        val meaningful = flattenedSemantics().filter {
            !it.config.getOrNull(SemanticsProperties.Text).isNullOrEmpty()
        }
        assertFalse("expected meaningful semantics", meaningful.isEmpty())
        meaningful.forEach {
            assertTrue("zero-width meaningful node: ${it.config}", it.boundsInRoot.width > 0f)
            assertTrue("zero-height meaningful node: ${it.config}", it.boundsInRoot.height > 0f)
        }
        assertMinimumTarget(
            rule.onNodeWithText(string(R.string.retry, Locale.ITALIAN)).fetchSemanticsNode(),
            "Italian retry at 200%",
        )
    }

    private fun transaction() = FinanceTransaction(
        id = "a11y-transaction",
        timestamp = Instant.parse("2026-09-15T12:00:00Z"),
        amount = BigDecimal("-10.00"),
        note = "coffee",
        categoryLabel = "Food",
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = null,
    )
}
