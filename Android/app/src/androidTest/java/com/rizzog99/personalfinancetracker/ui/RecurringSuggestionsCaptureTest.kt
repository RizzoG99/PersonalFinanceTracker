package com.rizzog99.personalfinancetracker.ui

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.and
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import com.rizzog99.personalfinancetracker.features.data.RecurringStepState
import com.rizzog99.personalfinancetracker.features.data.RecurringSuggestionsActions
import com.rizzog99.personalfinancetracker.features.data.RecurringSuggestionsContent
import com.rizzog99.personalfinancetracker.features.data.initialRecurringSelection
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
 * #295 import "Recurring" step (iOS `RecurrenceSuggestionsView` at b649dff, compared from source:
 * D-03). The production content and bottom-bar composables, photographed across language, theme,
 * width and text size, with the AC-01 fixture plus a two-payment €6 subscription that must start
 * unchecked.
 */
@RunWith(AndroidJUnit4::class)
class RecurringSuggestionsCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val dir: File get() = CaptureHarness.outputDir("recurring-suggestions")

    private fun suggestion(note: String, amount: String, count: Int, identical: Boolean, next: String, goalId: String? = null, category: String = "Bills") =
        RecurrenceSuggestion(
            frequency = RecurrenceFrequency.MONTHLY, interval = 1, amount = BigDecimal(amount), note = note, categoryLabel = category,
            categoryId = null, currencyCode = "EUR", occurrenceCount = count, nextDate = Instant.parse("${next}T12:00:00Z"),
            occurrenceDates = listOf(Instant.parse("2026-10-01T12:00:00Z")), amountsIdentical = identical, goalId = goalId,
        )

    /** The detector's order for the AC-01 fixture: strong ones first, biggest first. */
    private val fixture = listOf(
        suggestion("Affitto", "-750.00", 4, true, "2026-12-01"),
        suggestion("", "-200.00", 3, true, "2026-11-10", goalId = "goal-G", category = "→ Emergency fund"),
        suggestion("Luce", "-62.10", 3, false, "2026-11-05"),
        suggestion("App", "-6.00", 2, true, "2026-11-20"),
    )

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

    private val copy = mapOf(
        "en" to Copy(header = "4 recurring transactions found", plan3 = "Plan 3", plan4 = "Plan 4", done = "Done", selectAll = "Select all", about = "about"),
        "it" to Copy(header = "4 movimenti ricorrenti trovati", plan3 = "Pianifica 3", plan4 = "Pianifica 4", done = "Fatto", selectAll = "Seleziona tutto", about = "circa"),
    )

    private data class Copy(val header: String, val plan3: String, val plan4: String, val done: String, val selectAll: String, val about: String)

    @Test
    fun ac01_recurringStepAcrossLanguageThemeWidthAndTextSize() {
        val cell = mutableStateOf(cells.first())
        val state = mutableStateOf<RecurringStepState>(RecurringStepState.Found(fixture))
        val selected = mutableStateOf(initialRecurringSelection(fixture))
        val defaultLocale = Locale.getDefault()

        rule.setContent {
            val current = cell.value
            val context = CaptureHarness.localeContext(LocalContext.current, current.locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = current.widthDp
                fontScale = current.fontScale
            }
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(LocalDensity.current.density, current.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = current.theme) {
                    Surface(color = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface, modifier = Modifier.fillMaxSize()) {
                        Column(Modifier.width(current.widthDp.dp).testTag(HOST)) {
                            Column(
                                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(16.dp),
                            ) {
                                RecurringSuggestionsContent(
                                    state = state.value,
                                    categories = emptyList(),
                                    selected = selected.value,
                                    enabled = true,
                                    onSelectedChange = { selected.value = it },
                                )
                            }
                            RecurringSuggestionsActions(
                                hasSuggestions = (state.value as? RecurringStepState.Found)?.suggestions?.isNotEmpty() == true,
                                selectedCount = selected.value.size,
                                saving = false,
                                saveFailed = false,
                                onSkip = {},
                                onConfirm = {},
                                onDone = {},
                            )
                        }
                    }
                }
            }
        }

        val index = StringBuilder("cell,locale,widthDp,theme,fontScale,png,semantics\n")
        try {
            cells.forEach { c ->
                // Formatters read the JVM default locale, not the composition's.
                Locale.setDefault(c.locale ?: Locale.ENGLISH)
                cell.value = c
                state.value = RecurringStepState.Found(fixture)
                selected.value = initialRecurringSelection(fixture)
                rule.waitForIdle()
                val text = copy.getValue(c.locale?.language ?: "en")

                rule.onNodeWithTag(HOST).assertWidthIsEqualTo(c.widthDp.dp)
                rule.onNodeWithText(text.header).assertExists()
                rule.onNodeWithText(text.plan3).assertExists()
                rule.onNode(isToggleable() and hasContentDescription("Affitto", substring = true)).assertIsOn()
                rule.onNode(isToggleable() and hasContentDescription("App,", substring = true)).assertIsOff()
                rule.onNode(isToggleable() and hasContentDescription("Luce", substring = true) and hasContentDescription(text.about, substring = true)).assertExists()
                rule.onNodeWithText("≈", substring = true).assertExists()

                CaptureHarness.writePng(rule, dir, c.id)
                CaptureHarness.writeSemantics(rule, dir, c.id)
                index.append("${c.id},${c.locale?.language ?: "en"},${c.widthDp},${c.theme},${c.fontScale},${c.id}.png,${c.id}.txt\n")

                rule.onNode(hasText(text.selectAll)).performClick()
                rule.onNodeWithText(text.plan4).assertExists()
            }

            // The remaining states, once each in English.
            Locale.setDefault(Locale.ENGLISH)
            cell.value = cells.first()
            listOf(
                "state-zero-selected" to { state.value = RecurringStepState.Found(fixture); selected.value = emptySet() },
                "state-error" to { state.value = RecurringStepState.DetectionFailed },
                "state-loading" to { state.value = RecurringStepState.Loading },
                "state-empty" to { state.value = RecurringStepState.Found(emptyList()) },
            ).forEach { (id, apply) ->
                apply()
                rule.waitForIdle()
                when (id) {
                    "state-zero-selected" -> rule.onNodeWithText(copy.getValue("en").done).assertExists()
                    "state-error" -> rule.onNodeWithText("Couldn't check for recurring transactions", substring = true).assertExists()
                    "state-empty" -> rule.onNodeWithText("No repeating transactions found", substring = true).assertExists()
                }
                CaptureHarness.writeSemantics(rule, dir, id)
                if (id != "state-loading") CaptureHarness.writePng(rule, dir, id) // the spinner never idles
                index.append("$id,en,411,LIGHT,1.0,$id.png,$id.txt\n")
            }
        } finally {
            Locale.setDefault(defaultLocale)
        }
        File(dir, "index.csv").writeText(index.toString())
        assertEquals(cells.size + 4, File(dir, "index.csv").readLines().drop(1).count { it.isNotBlank() })
        cells.forEach { assertTrue("missing ${it.id}.png", File(dir, "${it.id}.png").length() > 0) }
    }

    private companion object {
        const val HOST = "recurring-host"
    }
}
