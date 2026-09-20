package com.rizzog99.personalfinancetracker.ui

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.features.activity.ActivityContent
import com.rizzog99.personalfinancetracker.features.activity.ActivityUiState
import com.rizzog99.personalfinancetracker.ui.components.EmptyState
import com.rizzog99.personalfinancetracker.ui.components.ErrorState
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
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

/**
 * Parity `M1-UI-STATES` (#111): the reusable state primitives and the production `when` that
 * chooses between them, rendered rather than reasoned about.
 *
 * The state *machine* — which state a repository answer produces — is asserted in the JVM suite
 * `UiStateTransitionTest`. This suite asserts the other half: that each state renders the copy,
 * semantics and actions its AC requires, and that the production branch resolves to the right one.
 * `ActivityContent` is hosted directly (it is `internal` for exactly this) so the `when` under test
 * is the shipping one, not a copy.
 */
@RunWith(AndroidJUnit4::class)
class UiStateEvidenceTest {

    @get:Rule
    val rule = createComposeRule()

    /** Technical text that must never reach the screen (#111 AC-04). */
    private val technicalFragments = listOf(
        "SQLiteDiskIOException",
        "Exception",
        "SELECT",
        "/data/user/",
        "code 1802",
    )

    // ------------------------------------------------------------------ hosting

    /**
     * Renders [content] with an optional locale, width and font scale override.
     *
     * All three go through the composition locals production already reads, so what is under test
     * stays the production composable rather than a re-parameterised copy of it.
     */
    private fun host(
        locale: Locale? = null,
        widthDp: Int? = null,
        fontScale: Float = 1f,
        content: @Composable () -> Unit,
    ) {
        rule.setContent {
            val context = localeContext(LocalContext.current, locale)
            val configuration = Configuration(context.resources.configuration).apply {
                widthDp?.let { screenWidthDp = it }
                this.fontScale = fontScale
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, fontScale),
            ) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) { content() }
            }
        }
        rule.waitForIdle()
    }

    /** Same wrapping trick as `NavShellGraphTest`: swap resources, keep the Activity reachable. */
    private fun localeContext(base: Context, locale: Locale?): Context = locale?.let {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(it)) },
        )
        object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    } ?: base

    private fun string(id: Int, locale: Locale? = null): String {
        val base = androidx.test.platform.app.InstrumentationRegistry
            .getInstrumentation().targetContext
        return localeContext(base, locale).getString(id)
    }

    /**
     * Every string the user can actually read — `Text` values and content descriptions.
     *
     * Deliberately not `printToString()` on the tree: that dump includes semantics *property
     * names*, so `Selected = 'false'` on a filter chip matches a search for "SELECT" and the check
     * fails on a screen that leaked nothing. Reading the text values is the assertion that means
     * what it says.
     */
    private fun ComposeContentTestRule.visibleText(): List<String> {
        val collected = mutableListOf<String>()
        fun walk(node: SemanticsNode) {
            node.config.getOrNull(SemanticsProperties.Text)?.forEach { collected += it.text }
            node.config.getOrNull(SemanticsProperties.ContentDescription)?.let { collected += it }
            node.children.forEach(::walk)
        }
        walk(onRoot(useUnmergedTree = true).fetchSemanticsNode())
        return collected
    }

    private fun ComposeContentTestRule.assertNoTechnicalText() {
        val readable = visibleText()
        technicalFragments.forEach { fragment ->
            assertFalse(
                "user-readable copy leaked \"$fragment\" — copy on screen: $readable",
                readable.any { it.contains(fragment, ignoreCase = true) },
            )
        }
    }

    /** The touch target, not the painted box — the former is what a finger has to hit. */
    private fun ComposeContentTestRule.touchHeightDp(label: String): Float {
        val node = onNodeWithText(label).fetchSemanticsNode()
        return with(node.layoutInfo.density) { node.touchBoundsInRoot.height.toDp().value }
    }

    // ------------------------------------------------------------- AC-01 loading

    @Test
    fun ac01_loadingReportsIndeterminateProgressAndALocalizedLabel() {
        host { LoadingState(modifier = Modifier.fillMaxSize()) }

        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.ProgressBarRangeInfo,
                ProgressBarRangeInfo.Indeterminate,
            ),
        ).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.loading)).assertIsDisplayed()
    }

    /**
     * The live region lives on the label, not the column (#111 AC-01's announcement policy). On the
     * column it watched a node with no text of its own, so it could never announce anything useful
     * while still being a region TalkBack polls.
     */
    @Test
    fun ac01_loadingAnnouncesThroughAPoliteLiveRegionOnTheLabel() {
        host { LoadingState(modifier = Modifier.fillMaxSize()) }

        rule.onNodeWithText(string(R.string.loading)).assert(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                androidx.compose.ui.semantics.LiveRegionMode.Polite,
            ),
        )
    }

    @Test
    fun ac01_loadingIsItalianOnAnItalianDevice() {
        host(locale = Locale.ITALIAN) { LoadingState(modifier = Modifier.fillMaxSize()) }

        rule.onNodeWithText(string(R.string.loading, Locale.ITALIAN)).assertIsDisplayed()
        assertEquals("Caricamento delle tue finanze", string(R.string.loading, Locale.ITALIAN))
    }

    // --------------------------------------------------------- AC-02 / AC-03 empty

    @Test
    fun ac02_emptyStateHasAHeadingAndInvokesItsActionExactlyOncePerTap() {
        var taps = 0
        host {
            EmptyState(
                title = string(R.string.empty_state_title),
                message = string(R.string.empty_state_message),
                action = {
                    Button(onClick = { taps++ }) { Text(string(R.string.add_transaction)) }
                },
            )
        }

        rule.onNodeWithText(string(R.string.empty_state_title))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithText(string(R.string.add_transaction)).performClick()
        rule.waitForIdle()

        assertEquals("one activation runs the action exactly once", 1, taps)

        rule.onNodeWithText(string(R.string.add_transaction)).performClick()
        rule.waitForIdle()
        assertEquals("and a second activation runs it once more, not twice", 2, taps)
    }

    /**
     * AC-06's target-size contract, measured on the **touch** bounds.
     *
     * A Material 3 `Button` paints at 40dp high, which is why asserting the layout box fails. What
     * a finger has to hit is `touchBoundsInRoot`, which `minimumInteractiveComponentSize` expands
     * to the platform's 48dp minimum. Asserting the painted box instead would report a defect that
     * does not exist; asserting nothing would miss one that does.
     */
    @Test
    fun ac06_emptyStateActionMeetsTheTouchTargetContract() {
        host {
            EmptyState(
                title = string(R.string.empty_state_title),
                message = string(R.string.empty_state_message),
                action = { Button(onClick = {}) { Text(string(R.string.add_transaction)) } },
            )
        }

        val label = string(R.string.add_transaction)
        rule.onNodeWithText(label).assertHasClickAction().assertWidthIsAtLeast(48.dp)
        val touchHeight = rule.touchHeightDp(label)
        assertTrue(
            "touch target is ${touchHeight}dp high, below the 48dp minimum",
            touchHeight >= 47.5f,
        )
    }

    // ------------------------------------------------------------ AC-04 error

    @Test
    fun ac04_errorStateExplainsTheFailureAndOffersRetry() {
        host {
            ErrorState(message = string(R.string.error_state_message), onRetry = {})
        }

        rule.onNodeWithText(string(R.string.error_state_title))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithText(string(R.string.error_state_message)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.retry)).assertIsDisplayed().assertHasClickAction()
        rule.assertNoTechnicalText()
    }

    @Test
    fun ac04_errorStateIsItalianOnAnItalianDevice() {
        host(locale = Locale.ITALIAN) {
            ErrorState(message = string(R.string.error_state_message, Locale.ITALIAN), onRetry = {})
        }

        rule.onNodeWithText(string(R.string.error_state_title, Locale.ITALIAN)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.retry, Locale.ITALIAN)).assertIsDisplayed()
        assertEquals("Riprova", string(R.string.retry, Locale.ITALIAN))
    }

    // ------------------------------------------------------------ AC-05 retry

    @Test
    fun ac05_retryInvokesTheSuppliedActionExactlyOncePerActivation() {
        var retries = 0
        host { ErrorState(message = string(R.string.error_state_message), onRetry = { retries++ }) }

        rule.onNodeWithText(string(R.string.retry)).performClick()
        rule.waitForIdle()
        assertEquals(1, retries)

        repeat(3) {
            rule.onNodeWithText(string(R.string.retry)).performClick()
            rule.waitForIdle()
        }
        assertEquals("each activation counts once — no doubled or swallowed taps", 4, retries)
    }

    // -------------------------------------- the production branch (#133's defect)

    private fun activityContent(state: ActivityUiState, onClear: () -> Unit = {}) =
        @Composable {
            ActivityContent(
                state = state,
                error = null,
                onSearchChange = {},
                onTypeFilterChange = {},
                onClearError = {},
                onClearSearchAndFilters = onClear,
                onRetry = {},
                onAdd = {},
                onEdit = {},
                onDelete = {},
                modifier = Modifier.fillMaxSize(),
            )
        }

    private fun transaction() = FinanceTransaction(
        id = "t1",
        timestamp = Instant.parse("2026-09-15T12:00:00Z"),
        amount = BigDecimal("-10.00"),
        note = "coffee",
        categoryLabel = "Food",
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = null,
    )

    @Test
    fun ac02_anEmptyLedgerShowsFirstRunCopyAndNotTheNoResultsCopy() {
        host {
            activityContent(ActivityUiState(isLoading = false))()
        }

        rule.onNodeWithText(string(R.string.empty_state_title)).assertIsDisplayed()
        rule.onAllNodes(hasText(string(R.string.no_matching_transactions)))
            .fetchSemanticsNodes().let {
                assertEquals("first-run copy must not carry the no-results heading", 0, it.size)
            }
    }

    @Test
    fun ac03_aQueryThatMatchesNothingShowsNoResultsAndNotFirstRunCopy() {
        host {
            activityContent(
                ActivityUiState(
                    isLoading = false,
                    allTransactions = listOf(transaction()),
                    visibleTransactions = emptyList(),
                    searchText = "zzzz",
                    filters = TransactionFilters(),
                ),
            )()
        }

        rule.onNodeWithText(string(R.string.no_matching_transactions)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.clear_search_and_filters))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onAllNodes(hasText(string(R.string.empty_state_title)))
            .fetchSemanticsNodes().let {
                assertEquals("no-results must not show onboarding copy", 0, it.size)
            }
    }

    /**
     * The load-bearing one. A read failure also leaves `allTransactions` empty, so resolving the
     * branches the other way round renders "Nothing here yet — add your first transaction" over a
     * ledger that is still intact on disk. That is #133 verbatim.
     */
    @Test
    fun ac02_aFailedReadShowsTheErrorStateAndNeverTheFirstRunCopy() {
        host {
            activityContent(ActivityUiState(isLoading = false, isError = true))()
        }

        rule.onNodeWithText(string(R.string.error_state_title)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.retry)).performScrollTo().assertIsDisplayed()
        rule.onAllNodes(hasText(string(R.string.empty_state_title)))
            .fetchSemanticsNodes().let {
                assertEquals(
                    "a failed read must never be dressed up as a first run",
                    0,
                    it.size,
                )
            }
        rule.assertNoTechnicalText()
    }

    @Test
    fun ac01_activityShowsLoadingAndNeitherEmptyNorErrorCopy() {
        host { activityContent(ActivityUiState(isLoading = true))() }

        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.ProgressBarRangeInfo,
                ProgressBarRangeInfo.Indeterminate,
            ),
        ).assertIsDisplayed()
        listOf(R.string.empty_state_title, R.string.error_state_title).forEach { id ->
            rule.onAllNodes(hasText(string(id))).fetchSemanticsNodes().let {
                assertEquals("loading must not also render a settled state", 0, it.size)
            }
        }
    }

    // --------------------------------------------------- AC-06 layout and scaling

    /**
     * Italian copy at a 2.0 font scale on the narrowest supported width is where truncation and
     * off-screen actions actually appear, so that is the cell asserted rather than the default one.
     * `performScrollTo` before `assertIsDisplayed` is the point: finding the node in the semantics
     * tree proves it exists, not that a user can reach it.
     */
    @Test
    fun ac06_italianErrorCopyAtLargeFontOnACompactWidthKeepsRetryReachable() {
        host(locale = Locale.ITALIAN, widthDp = 320, fontScale = 2.0f) {
            activityContent(ActivityUiState(isLoading = false, isError = true))()
        }

        val label = string(R.string.retry, Locale.ITALIAN)
        rule.onNodeWithText(string(R.string.error_state_title, Locale.ITALIAN))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onNodeWithText(label)
            .performScrollTo()
            .assertIsDisplayed()
            .assertHasClickAction()
        assertTrue(
            "the action stays a full-size touch target at a 2.0 font scale",
            rule.touchHeightDp(label) >= 47.5f,
        )
    }

    @Test
    fun ac06_italianFirstRunCopyAtLargeFontKeepsItsActionReachable() {
        host(locale = Locale.ITALIAN, widthDp = 320, fontScale = 2.0f) {
            activityContent(ActivityUiState(isLoading = false))()
        }

        val label = string(R.string.add_transaction, Locale.ITALIAN)
        rule.onNodeWithText(string(R.string.empty_state_title, Locale.ITALIAN))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onNodeWithText(label)
            .performScrollTo()
            .assertIsDisplayed()
            .assertHasClickAction()
        assertTrue(
            "the action stays a full-size touch target at a 2.0 font scale",
            rule.touchHeightDp(label) >= 47.5f,
        )
    }

    @Test
    fun ac06_theErrorStateHoldsUpOnAWideLayout() {
        host(widthDp = 900) {
            activityContent(ActivityUiState(isLoading = false, isError = true))()
        }

        rule.onNodeWithText(string(R.string.error_state_title)).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.retry)).performScrollTo().assertIsDisplayed()
    }
}
