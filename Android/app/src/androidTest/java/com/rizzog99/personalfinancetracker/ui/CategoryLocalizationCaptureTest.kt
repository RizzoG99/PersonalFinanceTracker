package com.rizzog99.personalfinancetracker.ui

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ActivityContent
import com.rizzog99.personalfinancetracker.features.activity.ActivityUiState
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsContent
import com.rizzog99.personalfinancetracker.features.categories.CategorySettingsUiState
import com.rizzog99.personalfinancetracker.domain.insights.CategoryTrend
import com.rizzog99.personalfinancetracker.domain.insights.TrendDirection
import com.rizzog99.personalfinancetracker.features.insights.CategoryTrendRow
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #291 capture matrix: Activity rows, the Categories list and Insights category rows, with a
 * built-in (Groceries), a custom category (Palestra, dumbbell, pink) and a `creditcard.fill` one,
 * across EN/IT, light/dark, compact/wide and default/large text. Production composables with the
 * same content colour their `Scaffold` supplies (#111).
 */
@RunWith(AndroidJUnit4::class)
class CategoryLocalizationCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val outputDir: File get() = CaptureHarness.outputDir("category-localization")

    private val cells = listOf(
        CaptureHarness.Cell("en-light-compact"),
        CaptureHarness.Cell("it-light-compact", locale = Locale.ITALIAN),
        CaptureHarness.Cell("it-dark-compact", locale = Locale.ITALIAN, theme = ThemeMode.DARK),
        CaptureHarness.Cell("it-light-wide", locale = Locale.ITALIAN, widthDp = 900),
        CaptureHarness.Cell("it-light-compact-large-text", locale = Locale.ITALIAN, fontScale = 2.0f),
    )
    private val hosts = listOf("activity", "categories", "insights")

    @Test
    fun captureTheMatrix() {
        val cell = mutableStateOf(cells.first())
        val host = mutableStateOf(hosts.first())
        rule.setContent {
            val current = cell.value
            val context = CaptureHarness.localeContext(LocalContext.current, current.locale)
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
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.surface,
                        contentColor = MaterialTheme.colorScheme.onSurface,
                    ) { Content(host.value) }
                }
            }
        }

        hosts.forEach { hostId ->
            host.value = hostId
            cells.forEach { c ->
                cell.value = c
                rule.waitForIdle()
                val italian = c.locale == Locale.ITALIAN
                // The built-in reads in the cell's language; the custom name never changes.
                // Text or content description: an Insights row (#303) speaks its name as one node.
                fun named(text: String) = rule.onAllNodes(hasText(text, substring = true) or hasContentDescription(text, substring = true))
                    .fetchSemanticsNodes().size
                assertTrue("$hostId ${c.id}", named(if (italian) "Spesa" else "Groceries") > 0)
                assertEquals("$hostId ${c.id}", 0, named(if (italian) "Groceries" else "Spesa"))
                assertTrue("$hostId ${c.id}", named("Palestra") > 0)
                val name = "$hostId--${c.id}"
                CaptureHarness.writePng(rule, outputDir, name)
                CaptureHarness.writeSemantics(rule, outputDir, name)
            }
        }
    }

    @Composable
    private fun Content(hostId: String) {
        when (hostId) {
            "activity" -> ActivityContent(
                state = ActivityUiState(isLoading = false, allTransactions = ROWS, visibleTransactions = ROWS, categories = CATEGORIES),
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
            "categories" -> CategorySettingsContent(
                state = CategorySettingsUiState(categories = CATEGORIES, isLoading = false),
                onAdd = {},
                onEdit = {},
                modifier = Modifier.fillMaxSize(),
            )
            else -> Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                fun trend(label: String, amount: String, share: Double, category: Int) =
                    CategoryTrend(label, BigDecimal(amount), share, 0.0, TrendDirection.FLAT, isNew = false, category = CATEGORIES[category])
                CategoryTrendRow(trend("Palestra", "40.00", 70.0, 1), isIncome = false, currencyCode = "EUR") {}
                CategoryTrendRow(trend("Groceries", "12.50", 22.0, 0), isIncome = false, currencyCode = "EUR") {}
                CategoryTrendRow(trend("Carta", "4.50", 8.0, 2), isIncome = false, currencyCode = "EUR") {}
            }
        }
    }

    private companion object {
        val CATEGORIES = listOf(
            FinanceCategory("groceries", "Groceries", "cart", TransactionType.EXPENSE, "categoryGreen", null, "EUR"),
            FinanceCategory("palestra", "Palestra", "dumbbell", TransactionType.EXPENSE, "categoryPink", null, "EUR"),
            FinanceCategory("carta", "Carta", "creditcard.fill", TransactionType.EXPENSE, "categoryIndigo", null, "EUR"),
        )

        fun row(id: String, amount: String, category: FinanceCategory) = FinanceTransaction(
            id = id, timestamp = Instant.parse("2026-09-15T12:00:00Z"), amount = BigDecimal(amount), note = "",
            categoryLabel = category.name, categoryId = category.id, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
        )

        val ROWS = listOf(row("g", "-12.50", CATEGORIES[0]), row("p", "-40.00", CATEGORIES[1]), row("c", "-4.50", CATEGORIES[2]))
    }
}
