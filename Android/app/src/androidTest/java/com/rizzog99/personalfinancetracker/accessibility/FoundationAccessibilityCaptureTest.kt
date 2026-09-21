package com.rizzog99.personalfinancetracker.accessibility

import android.content.res.Configuration
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ActivityContent
import com.rizzog99.personalfinancetracker.features.activity.ActivityUiState
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsContent
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsUiState
import com.rizzog99.personalfinancetracker.features.security.PinUnlockScreen
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.CaptureHarness.Cell
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

/** Screenshot + parsed-semantics evidence matrix for #113. */
@RunWith(AndroidJUnit4::class)
class FoundationAccessibilityCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private enum class Host { SHELL, LOADING, EMPTY, NO_RESULTS, ERROR, RETRY, RECOVERED, RECOVERY, CATEGORY, PIN }

    private data class Spec(val host: Host, val cell: Cell) {
        val name: String get() = "${host.name.lowercase()}--${cell.id}"
    }

    @Test
    fun captureAndInspectShellMatrix() {
        val specs = buildList {
            listOf(Locale.ENGLISH, Locale.ITALIAN).forEach { locale ->
                listOf(411, 900).forEach { width ->
                    listOf(ThemeMode.LIGHT, ThemeMode.DARK).forEach { theme ->
                        listOf(1f, 2f).forEach { font ->
                            val language = if (locale == Locale.ITALIAN) "it" else "en"
                            add(
                                Spec(
                                    Host.SHELL,
                                    Cell(
                                        id = "$language-${width}dp-${theme.name.lowercase()}-${font}x",
                                        locale = locale,
                                        widthDp = width,
                                        theme = theme,
                                        fontScale = font,
                                    ),
                                ),
                            )
                        }
                    }
                }
            }
        }
        capture(specs, "m1-a11y-base/shell")
    }

    @Test
    fun captureAndInspectSharedStateMatrix() {
        val specs = listOf(
            spec(Host.LOADING, "en-compact-light-1x", Locale.ENGLISH, 411, ThemeMode.LIGHT, 1f),
            spec(Host.LOADING, "it-compact-dark-2x", Locale.ITALIAN, 411, ThemeMode.DARK, 2f),
            spec(Host.EMPTY, "en-wide-dark-2x", Locale.ENGLISH, 900, ThemeMode.DARK, 2f),
            spec(Host.EMPTY, "it-wide-light-1x", Locale.ITALIAN, 900, ThemeMode.LIGHT, 1f),
            spec(Host.NO_RESULTS, "en-compact-dark-2x", Locale.ENGLISH, 411, ThemeMode.DARK, 2f),
            spec(Host.NO_RESULTS, "it-wide-dark-1x", Locale.ITALIAN, 900, ThemeMode.DARK, 1f),
            spec(Host.ERROR, "en-wide-light-2x", Locale.ENGLISH, 900, ThemeMode.LIGHT, 2f),
            spec(Host.ERROR, "it-compact-light-1x", Locale.ITALIAN, 411, ThemeMode.LIGHT, 1f),
            spec(Host.RETRY, "en-compact-light-2x", Locale.ENGLISH, 411, ThemeMode.LIGHT, 2f),
            spec(Host.RETRY, "it-wide-dark-2x", Locale.ITALIAN, 900, ThemeMode.DARK, 2f),
            spec(Host.RECOVERED, "en-wide-dark-1x", Locale.ENGLISH, 900, ThemeMode.DARK, 1f),
            spec(Host.RECOVERED, "it-compact-dark-1x", Locale.ITALIAN, 411, ThemeMode.DARK, 1f),
        )
        capture(specs, "m1-a11y-base/states")
    }

    @Test
    fun captureAndInspectRecoveryCategoryAndPinMatrix() {
        val specs = listOf(
            spec(Host.RECOVERY, "en-compact-light-1x", Locale.ENGLISH, 411, ThemeMode.LIGHT, 1f),
            spec(Host.RECOVERY, "it-compact-dark-2x", Locale.ITALIAN, 411, ThemeMode.DARK, 2f),
            spec(Host.RECOVERY, "en-wide-dark-2x", Locale.ENGLISH, 900, ThemeMode.DARK, 2f),
            spec(Host.RECOVERY, "it-wide-light-1x", Locale.ITALIAN, 900, ThemeMode.LIGHT, 1f),
            spec(Host.CATEGORY, "en-compact-dark-2x", Locale.ENGLISH, 411, ThemeMode.DARK, 2f),
            spec(Host.CATEGORY, "it-compact-light-1x", Locale.ITALIAN, 411, ThemeMode.LIGHT, 1f),
            spec(Host.CATEGORY, "en-wide-light-2x", Locale.ENGLISH, 900, ThemeMode.LIGHT, 2f),
            spec(Host.CATEGORY, "it-wide-dark-1x", Locale.ITALIAN, 900, ThemeMode.DARK, 1f),
            spec(Host.PIN, "en-compact-light-1x", Locale.ENGLISH, 411, ThemeMode.LIGHT, 1f),
            spec(Host.PIN, "it-compact-dark-2x", Locale.ITALIAN, 411, ThemeMode.DARK, 2f),
            spec(Host.PIN, "en-wide-dark-2x", Locale.ENGLISH, 900, ThemeMode.DARK, 2f),
            spec(Host.PIN, "it-wide-light-1x", Locale.ITALIAN, 900, ThemeMode.LIGHT, 1f),
        )
        capture(specs, "m1-a11y-base/secondary")
    }

    private fun spec(
        host: Host,
        id: String,
        locale: Locale,
        width: Int,
        theme: ThemeMode,
        font: Float,
    ) = Spec(host, Cell(id, locale, width, theme, font))

    private fun capture(specs: List<Spec>, directory: String) {
        val deviceWidthDp = InstrumentationRegistry.getInstrumentation()
            .targetContext.resources.configuration.screenWidthDp
        val deviceIsWide = deviceWidthDp >= 840
        val widthKind = if (deviceIsWide) "wide" else "compact"
        val matchingSpecs = specs.filter { (it.cell.widthDp >= 840) == deviceIsWide }
        assertFalse("$directory has no $widthKind cells", matchingSpecs.isEmpty())
        val current = mutableStateOf(matchingSpecs.first())
        val expectedHash = PinCodec.hash("999999", "capture-salt")
        rule.setContent {
            val spec = current.value
            val context = CaptureHarness.localeContext(LocalContext.current, spec.cell.locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = spec.cell.widthDp
                fontScale = spec.cell.fontScale
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, spec.cell.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = spec.cell.theme) {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        key(spec.name) {
                            host(spec.host, expectedHash)
                        }
                    }
                }
            }
        }

        val dir = CaptureHarness.outputDir(directory)
        val index = StringBuilder("host,cell,locale,widthDp,theme,fontScale,png,semantics\n")
        matchingSpecs.forEach { spec ->
            current.value = spec
            rule.waitForIdle()
            if (spec.host == Host.PIN) {
                repeat(6) {
                    rule.onNodeWithText("0").performSemanticsAction(SemanticsActions.OnClick) { it() }
                    rule.waitForIdle()
                }
                val error = localizedString(R.string.pin_incorrect, spec.cell.locale)
                rule.waitUntil(3_000) { rule.onAllNodes(hasText(error)).fetchSemanticsNodes().isNotEmpty() }
                rule.onNodeWithText(error).assertIsDisplayed()
            }
            inspect(spec)
            CaptureHarness.writePng(rule, dir, spec.name)
            CaptureHarness.writeSemantics(rule, dir, spec.name)
            index.append(spec.host.name.lowercase()).append(',')
                .append(spec.cell.id).append(',')
                .append(spec.cell.locale?.language ?: "en").append(',')
                .append(spec.cell.widthDp).append(',')
                .append(spec.cell.theme).append(',')
                .append(spec.cell.fontScale).append(',')
                .append(spec.name).append(".png,")
                .append(spec.name).append(".txt\n")
        }
        dir.resolve("index-$widthKind.csv").writeText(index.toString())
        val combined = StringBuilder("host,cell,locale,widthDp,theme,fontScale,png,semantics\n")
        specs.filter { spec ->
            dir.resolve("${spec.name}.png").exists() && dir.resolve("${spec.name}.txt").exists()
        }.forEach { spec -> appendIndexRow(combined, spec) }
        dir.resolve("index.csv").writeText(combined.toString())
    }

    private fun appendIndexRow(index: StringBuilder, spec: Spec) {
        index.append(spec.host.name.lowercase()).append(',')
            .append(spec.cell.id).append(',')
            .append(spec.cell.locale?.language ?: "en").append(',')
            .append(spec.cell.widthDp).append(',')
            .append(spec.cell.theme).append(',')
            .append(spec.cell.fontScale).append(',')
            .append(spec.name).append(".png,")
            .append(spec.name).append(".txt\n")
    }

    @androidx.compose.runtime.Composable
    private fun host(host: Host, expectedHash: String) {
        when (host) {
            Host.SHELL -> PersonalFinanceNavHost()
            Host.LOADING, Host.RETRY -> activity(ActivityUiState(isLoading = true))
            Host.EMPTY -> activity(ActivityUiState(isLoading = false))
            Host.NO_RESULTS -> activity(
                ActivityUiState(
                    isLoading = false,
                    allTransactions = listOf(transaction()),
                    visibleTransactions = emptyList(),
                    searchText = "missing",
                ),
            )
            Host.ERROR -> activity(ActivityUiState(isLoading = false, isError = true))
            Host.RECOVERED -> activity(
                ActivityUiState(
                    isLoading = false,
                    allTransactions = listOf(transaction()),
                    visibleTransactions = listOf(transaction()),
                ),
            )
            Host.RECOVERY -> StoredDataUnavailableState(
                message = androidx.compose.ui.res.stringResource(R.string.stored_data_unavailable_database),
            )
            Host.CATEGORY -> CategorySettingsContent(
                state = CategorySettingsUiState(isLoading = true),
                onAdd = {},
                onEdit = {},
                modifier = Modifier.fillMaxSize(),
            )
            Host.PIN -> PinUnlockScreen(
                expectedHash = expectedHash,
                expectedSalt = "capture-salt",
                biometricEnabled = false,
                onUnlocked = {},
            )
        }
    }

    @androidx.compose.runtime.Composable
    private fun activity(state: ActivityUiState) {
        ActivityContent(
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
    }

    private fun inspect(spec: Spec) {
        val nodes = flatten(rule.onRoot(useUnmergedTree = true).fetchSemanticsNode())
        val allMeaningful = nodes.filter {
            !it.config.getOrNull(SemanticsProperties.Text).isNullOrEmpty() ||
                !it.config.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty() ||
                it.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo) != null
        }
        // #112 D-05 is intentionally still visible in the shell screenshots, but Home's pulse
        // card belongs to #88. The #113 shell assertion covers only chrome: primary tabs, the
        // screen heading, and the compact actions shared by the foundation shell.
        val meaningful = if (spec.host == Host.SHELL) {
            val locale = spec.cell.locale ?: Locale.ENGLISH
            val chromeDescriptions = setOf(
                localizedString(R.string.add_transaction, locale),
                localizedString(R.string.toggle_theme, locale),
                localizedString(R.string.settings_title, locale),
                localizedString(R.string.hide_balance, locale),
                localizedString(R.string.show_balance, locale),
            )
            val screenHeading = localizedString(R.string.home_title, locale)
            allMeaningful.filter { node ->
                node.config.getOrNull(SemanticsProperties.Role) == Role.Tab ||
                    (node.config.getOrNull(SemanticsProperties.Heading) != null &&
                        node.config.getOrNull(SemanticsProperties.Text)?.any { it.text == screenHeading } == true) ||
                    node.config.getOrNull(SemanticsProperties.ContentDescription)
                        ?.any(chromeDescriptions::contains) == true
            }
        } else {
            allMeaningful
        }
        assertFalse("${spec.name} exposed no meaningful accessibility nodes", meaningful.isEmpty())
        meaningful.forEach { node ->
            assertTrue("${spec.name} zero-width node: ${node.config}", node.boundsInRoot.width > 0f)
            assertTrue("${spec.name} zero-height node: ${node.config}", node.boundsInRoot.height > 0f)
        }
        val actions = if (spec.host == Host.SHELL) {
            nodes.filter { node ->
                node.config.getOrNull(SemanticsProperties.Role) == Role.Tab ||
                    node.config.getOrNull(SemanticsProperties.ContentDescription)?.any { description ->
                        meaningful.any { description in it.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty() }
                    } == true
            }
        } else {
            nodes
        }
        actions.filter { it.config.getOrNull(SemanticsActions.OnClick) != null }.forEach { node ->
            with(node.layoutInfo.density) {
                assertTrue("${spec.name} undersized action width: ${node.config}", node.touchBoundsInRoot.width.toDp().value >= 47.5f)
                assertTrue("${spec.name} undersized action height: ${node.config}", node.touchBoundsInRoot.height.toDp().value >= 47.5f)
            }
        }

        if (spec.host == Host.SHELL) {
            val tabs = nodes.filter { it.config.getOrNull(SemanticsProperties.Role) == Role.Tab }
            assertEquals("${spec.name} primary tab count", 3, tabs.size)
            assertEquals("${spec.name} selected tab count", 1, tabs.count { it.config.getOrNull(SemanticsProperties.Selected) == true })
        }
    }

    private fun flatten(node: SemanticsNode): List<SemanticsNode> =
        listOf(node) + node.children.flatMap(::flatten)

    private fun localizedString(id: Int, locale: Locale?): String {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        return CaptureHarness.localeContext(context, locale).getString(id)
    }

    private fun transaction() = FinanceTransaction(
        id = "a11y-capture",
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
