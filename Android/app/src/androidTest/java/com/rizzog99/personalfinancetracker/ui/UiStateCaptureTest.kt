package com.rizzog99.personalfinancetracker.ui

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import android.graphics.Bitmap
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ActivityContent
import com.rizzog99.personalfinancetracker.features.activity.ActivityUiState
import com.rizzog99.personalfinancetracker.ui.components.ErrorState
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Parity `M1-UI-STATES` (#111): the visual matrix.
 *
 * These capture the **production** `ActivityContent` and the state primitives it renders, one PNG
 * and one semantics dump per cell, written to the app's external files dir for `adb pull`.
 *
 * Why here rather than by driving the app on a device: loading, error and retry-in-progress are not
 * reachable on an emulator without a seam that makes a Room read fail mid-session, and #111 chose
 * not to add a production hook purely to photograph a state. Capturing the shipping composable at a
 * given locale, width, theme and font scale is the honest alternative — it renders the same code
 * the device would, without pretending a device run happened. The two states that *are* reachable
 * for real, first-run empty and no-results, are additionally driven end-to-end on `MainActivity` in
 * `UiStateReachabilityTest`.
 */
@RunWith(AndroidJUnit4::class)
class UiStateCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val outputDir: File
        get() = File(
            InstrumentationRegistry.getInstrumentation().targetContext
                .getExternalFilesDir(null),
            "ui-states",
        ).apply { mkdirs() }

    /** One row of the matrix: an appearance/locale/width/font-scale combination. */
    private data class Cell(
        val id: String,
        val locale: Locale? = null,
        val widthDp: Int = 411,
        val theme: ThemeMode = ThemeMode.LIGHT,
        val fontScale: Float = 1f,
    )

    private val cells = listOf(
        Cell("en-light-compact"),
        Cell("it-light-compact", locale = Locale.ITALIAN),
        Cell("en-dark-compact", theme = ThemeMode.DARK),
        Cell("en-light-wide", widthDp = 900),
        Cell("it-light-compact-large-text", locale = Locale.ITALIAN, fontScale = 2.0f),
    )

    /** One column of the matrix: a state the production `when` can resolve to. */
    private val states = listOf(
        "01-loading" to ActivityUiState(isLoading = true),
        "02-first-run-empty" to ActivityUiState(isLoading = false),
        "03-no-results" to ActivityUiState(
            isLoading = false,
            allTransactions = listOf(sample()),
            visibleTransactions = emptyList(),
            searchText = "zzzz",
        ),
        "04-error" to ActivityUiState(isLoading = false, isError = true),
        // Retry-in-progress is the loading state re-entered by `retry()`; it renders identically
        // by construction, and is captured separately so the matrix does not imply otherwise.
        "05-retry-in-progress" to ActivityUiState(isLoading = true),
    )

    /**
     * One composition for the whole matrix — `setContent` may only be called once per test, so the
     * cell and the state are driven through `mutableStateOf` and the tree recomposes between
     * captures.
     */
    /**
     * The two production hosts these primitives render in. `activity-list` drops them into a
     * `LazyColumn` item below the search field; `fullscreen` fills a `Scaffold` content area, which
     * is how `HomeScreen` and `InsightsScreen` use them.
     */
    private val hosts = listOf("activity-list", "fullscreen")

    /**
     * Which states each host can actually reach.
     *
     * `fullscreen` — `HomeScreen` and `InsightsScreen` — has no no-results state at all: neither
     * screen has a query to return nothing. Capturing one anyway would just re-render the first-run
     * empty state under a name that claims otherwise, so the cell is left out of the matrix rather
     * than filled with a duplicate. Their first-run empty states are in-content cards
     * (`EmptyDashboardCard`, "set your first goal"), not this primitive, so they are out too.
     */
    private fun statesFor(hostId: String): List<Pair<String, ActivityUiState>> =
        if (hostId == "fullscreen") {
            states.filter { it.first in setOf("01-loading", "04-error", "05-retry-in-progress") }
        } else {
            states
        }

    @Test
    fun captureTheStateMatrix() {
        val cell = mutableStateOf(cells.first())
        val uiState = mutableStateOf(states.first().second)
        val host = mutableStateOf(hosts.first())

        rule.setContent {
            val current = cell.value
            val context = localeContext(LocalContext.current, current.locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = current.widthDp
                fontScale = current.fontScale
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, current.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = current.theme) {
                    // Mirrors what production gives this content: `ActivityScreen` hosts it in a
                    // `Scaffold(containerColor = surface, contentColor = onSurface)`. A bare `Box`
                    // with only a background sets no `LocalContentColor`, so `Text` falls back to
                    // black — which renders the dark cells black-on-black and would be reported as
                    // a contrast defect that production does not have. The harness has to supply
                    // the same content color the real host does.
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.surface,
                        contentColor = MaterialTheme.colorScheme.onSurface,
                    ) {
                        Content(host.value, uiState.value)
                    }
                }
            }
        }

        val index = StringBuilder("host,state,cell,locale,widthDp,theme,fontScale,png,semantics\n")
        hosts.forEach { hostId ->
            host.value = hostId
            statesFor(hostId).forEach { (stateId, state) ->
                cells.forEach { c ->
                    cell.value = c
                    uiState.value = state
                    rule.waitForIdle()
                    val name = "$hostId--$stateId--${c.id}"
                    writePng(name)
                    writeSemantics(name)
                    index.append(
                        "$hostId,$stateId,${c.id},${c.locale?.language ?: "en"},${c.widthDp}," +
                            "${c.theme},${c.fontScale},$name.png,$name.txt\n",
                    )
                }
            }
        }
        File(outputDir, "index.csv").writeText(index.toString())
    }

    @Composable
    private fun Content(hostId: String, state: ActivityUiState) {
        when (hostId) {
            // Activity: the states arrive as `LazyColumn` items below the search field and filter
            // chips, and the caller supplies only vertical padding.
            "activity-list" -> ActivityContent(
                state = state,
                error = null,
                onSearchChange = {},
                onTypeFilterChange = {},
                onClearError = {},
                onClearSearchAndFilters = {},
                onRetry = {},
                onAdd = {},
                onEdit = {},
                onDelete = {},
                modifier = Modifier.fillMaxSize(),
            )
            // Home and Insights: the same two primitives, but filling the whole Scaffold content
            // area, which is a different modifier chain and a different host. Capturing only the
            // Activity host would leave those call sites photographed nowhere, while the state map
            // on #111 lists all three.
            else -> when {
                state.isError -> ErrorState(
                    message = stringResource(R.string.error_state_message),
                    onRetry = {},
                    modifier = Modifier.fillMaxSize(),
                )
                else -> LoadingState(modifier = Modifier.fillMaxSize())
            }
        }
    }

    private fun writePng(name: String) {
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        File(outputDir, "$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    /**
     * The hierarchy half of the matrix: every readable string with its bounds, so a reviewer can
     * check for zero-size actions and clipped copy without eyeballing a PNG.
     */
    private fun writeSemantics(name: String) {
        val out = StringBuilder()
        fun walk(node: SemanticsNode, depth: Int) {
            val text = node.config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text }
            val description = node.config.getOrNull(SemanticsProperties.ContentDescription)
                ?.joinToString()
            val heading = node.config.getOrNull(SemanticsProperties.Heading) != null
            val progress = node.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo)
            val live = node.config.getOrNull(SemanticsProperties.LiveRegion)
            if (text != null || description != null || progress != null) {
                out.append(" ".repeat(depth * 2))
                    .append("text=").append(text)
                    .append(" desc=").append(description)
                    .append(" heading=").append(heading)
                    .append(" progress=").append(progress)
                    .append(" liveRegion=").append(live)
                    .append(" bounds=").append(node.boundsInRoot)
                    .append(" touch=").append(node.touchBoundsInRoot)
                    .append('\n')
            }
            node.children.forEach { walk(it, depth + 1) }
        }
        walk(rule.onRoot(useUnmergedTree = true).fetchSemanticsNode(), 0)
        File(outputDir, "$name.txt").writeText(out.toString())
    }

    private fun localeContext(base: Context, locale: Locale?): Context = locale?.let {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(it)) },
        )
        object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    } ?: base

    private companion object {
        fun sample() = FinanceTransaction(
            id = "t1",
            timestamp = Instant.parse("2026-09-15T12:00:00Z"),
            amount = BigDecimal("-12.50"),
            note = "coffee",
            categoryLabel = "Food",
            categoryId = null,
            currencyCode = "EUR",
            goalId = null,
            recurrenceRuleId = null,
        )
    }
}
