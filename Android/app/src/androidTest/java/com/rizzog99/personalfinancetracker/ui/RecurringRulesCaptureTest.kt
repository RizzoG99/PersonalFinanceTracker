package com.rizzog99.personalfinancetracker.ui

import android.content.res.Configuration
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasScrollToKeyAction
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.duplicateRuleIds
import com.rizzog99.personalfinancetracker.domain.recurrence.monthlySpend
import com.rizzog99.personalfinancetracker.domain.recurrence.nextOccurrence
import com.rizzog99.personalfinancetracker.domain.recurrence.title
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorContent
import com.rizzog99.personalfinancetracker.features.recurring.RecurringRuleRow
import com.rizzog99.personalfinancetracker.features.recurring.RecurringRulesContent
import com.rizzog99.personalfinancetracker.features.recurring.RecurringRulesUiState
import com.rizzog99.personalfinancetracker.features.recurring.cadenceLabel
import com.rizzog99.personalfinancetracker.ui.formatters.formatSignedCurrency
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #294 AC-01/04/06: the production Recurring content and the rule editor, photographed across
 * language, theme, width and text size (compared against iOS `RecurringView.swift` source: D-05).
 */
@RunWith(AndroidJUnit4::class)
class RecurringRulesCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val zone = ZoneId.of("Europe/Rome")
    private val now = Instant.parse("2026-11-21T11:00:00Z")
    private val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication

    private val bills = FinanceCategory("bills", "Bills", "receipt", TransactionType.EXPENSE, "categoryAmber", null, "EUR")

    private fun rule(id: String, note: String, amount: String, start: String, frequency: RecurrenceFrequency = RecurrenceFrequency.MONTHLY, interval: Int = 1) =
        RecurrenceRule(
            id = id, frequency = frequency, interval = interval, startDate = LocalDate.parse(start).atTime(10, 0).atZone(zone).toInstant(),
            endDate = null, lastMaterializedDate = null, amount = BigDecimal(amount), note = note, categoryLabel = "Bills",
            categoryId = "bills", currencyCode = "EUR", goalId = null,
        )

    private val rules = listOf(
        rule("gym", "Gym", "-30.00", "2026-11-10", RecurrenceFrequency.WEEKLY, interval = 2),
        rule("salary", "Salary", "2000.00", "2026-01-27"),
        rule("netflix", "Netflix", "-12.99", "2026-01-05"),
        rule("netflix2", "Netflix", "-15.99", "2026-02-10"),
        rule("insurance", "Car insurance with a long Italian-length name", "-1240.00", "2026-03-15", RecurrenceFrequency.YEARLY, interval = 2),
    )

    private val state: RecurringRulesUiState = run {
        val duplicates = duplicateRuleIds(rules)
        RecurringRulesUiState(
            isLoading = false,
            rows = rules.map { RecurringRuleRow(it, it.title(), it.nextOccurrence(now, zone), it.id in duplicates, bills) }.sortedBy { it.nextDate },
            monthlySpend = monthlySpend(rules),
            categories = listOf(bills),
        )
    }

    private val wideAvailable: Boolean
        get() = InstrumentationRegistry.getInstrumentation().targetContext.resources.configuration.screenWidthDp >= 900

    private val cells = buildList {
        add(CaptureHarness.Cell("en-light-compact"))
        add(CaptureHarness.Cell("it-light-compact", locale = Locale.ITALIAN))
        add(CaptureHarness.Cell("en-dark-compact", theme = ThemeMode.DARK))
        add(CaptureHarness.Cell("it-dark-compact", locale = Locale.ITALIAN, theme = ThemeMode.DARK))
        add(CaptureHarness.Cell("en-light-compact-large-text", fontScale = 2.0f))
        add(CaptureHarness.Cell("it-light-compact-large-text", locale = Locale.ITALIAN, fontScale = 2.0f))
        // Only where the device really is that wide: a 900 dp host on a phone is squeezed (#376).
        if (wideAvailable) {
            add(CaptureHarness.Cell("en-light-wide", widthDp = 900))
            add(CaptureHarness.Cell("it-dark-wide", locale = Locale.ITALIAN, widthDp = 900, theme = ThemeMode.DARK))
        }
    }

    private data class Copy(val active: String, val monthly: String, val duplicate: String, val stop: String, val frequency: String, val empty: String)

    private val copy = mapOf(
        "en" to Copy("Active", "Monthly spend", "Possible duplicate", "Stop", "Frequency: Monthly", "No recurring transactions yet"),
        "it" to Copy("Attivi", "Spesa mensile", "Possibile doppione", "Interrompi", "Frequenza: Ogni mese", "Ancora nessun movimento ricorrente"),
    )

    private fun host(cell: CaptureHarness.Cell, content: @Composable () -> Unit) {
        current.value = cell
        body.value = content
        rule.waitForIdle()
    }

    private val current = mutableStateOf(CaptureHarness.Cell("en-light-compact"))
    private val body = mutableStateOf<@Composable () -> Unit>({})

    private fun setUpHost() {
        rule.setContent {
            val c = current.value
            val context = CaptureHarness.localeContext(LocalContext.current, c.locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = c.widthDp
                fontScale = c.fontScale
            }
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(LocalDensity.current.density, c.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = c.theme) {
                    Surface(color = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface, modifier = Modifier.fillMaxSize()) {
                        androidx.compose.foundation.layout.Box(Modifier.wrapContentWidth(Alignment.Start).width(c.widthDp.dp).testTag(HOST)) {
                            body.value()
                        }
                    }
                }
            }
        }
    }

    private fun matrix(dirName: String, assertCell: (CaptureHarness.Cell, Copy) -> Unit, content: @Composable () -> Unit) {
        val dir = CaptureHarness.outputDir(dirName)
        val defaultLocale = Locale.getDefault()
        setUpHost()
        val index = StringBuilder("cell,locale,widthDp,theme,fontScale,png,semantics\n")
        try {
            cells.forEach { c ->
                // Formatters read the JVM default locale, not the composition's.
                Locale.setDefault(c.locale ?: Locale.ENGLISH)
                host(c, content)
                rule.onNodeWithTag(HOST).assertWidthIsEqualTo(c.widthDp.dp)
                assertCell(c, copy.getValue(c.locale?.language ?: "en"))
                CaptureHarness.writePng(rule, dir, c.id)
                CaptureHarness.writeSemantics(rule, dir, c.id)
                index.append("${c.id},${c.locale?.language ?: "en"},${c.widthDp},${c.theme},${c.fontScale},${c.id}.png,${c.id}.txt\n")
            }
        } finally {
            Locale.setDefault(defaultLocale)
        }
        File(dir, "index.csv").writeText(index.toString())
        cells.forEach { assertTrue("missing ${it.id}.png", File(dir, "${it.id}.png").length() > 0) }
    }

    @Test
    fun ac01_ac06_rulesListAcrossLanguageThemeWidthAndTextSize() {
        matrix(
            "recurring-rules",
            assertCell = { _, text ->
                rule.onNodeWithText(text.active).assertExists()
                rule.onNodeWithText(text.monthly).assertExists()
                rule.onNodeWithText(formatSignedCurrency(state.monthlySpend, "EUR")).assertExists()
                assertEquals(2, state.rows.count { it.isDuplicate })
                state.rows.forEach { row ->
                    val tag = "recurringRule-${row.rule.id}"
                    // A lazy list composes only what is on screen.
                    rule.onNode(hasScrollToKeyAction()).performScrollToKey(row.rule.id)
                    // One TalkBack element per rule: title, cadence/next date and amount, Edit and Stop.
                    rule.onAllNodesWithTag(tag).assertCountEquals(1)
                    rule.onAllNodes(hasTestTag(tag) and hasClickAction() and hasText(row.title, substring = true) and
                        hasText(formatSignedCurrency(row.rule.amount, "EUR"), substring = true)).assertCountEquals(1)
                    rule.onAllNodes(hasTestTag(tag) and hasText(text.duplicate, substring = true)).assertCountEquals(if (row.isDuplicate) 1 else 0)
                    val actions = rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsActions.CustomActions]
                    assertEquals(listOf(text.stop), actions.map { it.label })
                }
                rule.onNode(hasScrollToKeyAction()).performScrollToIndex(0)
            },
        ) {
            RecurringRulesContent(state = state, zoneId = zone, onSelect = {}, onStop = {})
        }
    }

    @Test
    fun ac02_ac06_ruleEditorAcrossLanguageThemeWidthAndTextSize() {
        val netflix = rules.first { it.id == "netflix" }
        val asTransaction = FinanceTransaction(netflix.id, netflix.startDate, netflix.amount, netflix.note, netflix.categoryLabel, netflix.categoryId, "EUR", null, null)
        matrix(
            "recurring-rule-editor",
            assertCell = { _, text ->
                rule.onNodeWithText(text.frequency).assertExists()
                rule.onAllNodes(isToggleable()).assertCountEquals(0)
            },
        ) {
            TransactionEditorContent(
                editingTransaction = asTransaction,
                categories = listOf(bills),
                receiptMappingRepository = app.receiptMappingRepository,
                onDismiss = {},
                onSave = { _, _, _ -> },
                ruleCadence = cadenceLabel(netflix.frequency, netflix.interval),
            )
        }
    }

    @Test
    fun ac04_emptyState() {
        matrix(
            "recurring-rules-empty",
            assertCell = { _, text -> rule.onNodeWithText(text.empty).assertExists() },
        ) {
            RecurringRulesContent(state = RecurringRulesUiState(isLoading = false), zoneId = zone, onSelect = {}, onStop = {})
        }
    }

    private companion object {
        const val HOST = "recurring-rules-host"
    }
}
