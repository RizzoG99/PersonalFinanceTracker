package com.rizzog99.personalfinancetracker.l10n

import android.content.res.Configuration
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.components.StoredDataUnavailableState
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Parity `M1-L10N-BASE` (#112) `AC-06`: the shell and the startup-recovery state photographed and
 * parsed across language, width, theme and text size.
 *
 * #111's matrix covered the shared states; this one covers what #111 explicitly left to #112 — the
 * navigation bar and rail, whose labels are the copy most likely to be truncated, and the recovery
 * screen, whose copy is the longest in the foundation. Both run through the same
 * [CaptureHarness] #111 uses, so there is one capture path rather than two that can drift.
 *
 * The run both writes evidence and asserts on it. A PNG nobody looks at proves nothing, so the
 * structural failures a reviewer would be looking for — a clipped or ellipsised destination label,
 * an action pushed off-screen, a zero-size node, a stale-language label — are asserted here from
 * the parsed semantics of every cell, and the images are for the judgements a machine should not
 * be making.
 */
@RunWith(AndroidJUnit4::class)
class FoundationLocaleCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val dir: File get() = CaptureHarness.outputDir("l10n-foundation")

    /**
     * Five cells, chosen to discriminate rather than to be exhaustive. Italian is the longer
     * language in every foundation string, so Italian at a 2.0 font scale on the narrowest width is
     * where truncation appears if it appears at all; wide is where the rail replaces the bar; dark
     * is where a theme-dependent text failure would show.
     */
    private val cells = listOf(
        CaptureHarness.Cell("en-light-compact"),
        CaptureHarness.Cell("it-light-compact", locale = Locale.ITALIAN),
        CaptureHarness.Cell("it-dark-compact", locale = Locale.ITALIAN, theme = ThemeMode.DARK),
        CaptureHarness.Cell("it-light-wide", locale = Locale.ITALIAN, widthDp = 900),
        CaptureHarness.Cell(
            "it-light-compact-large-text",
            locale = Locale.ITALIAN,
            fontScale = 2.0f,
        ),
    )

    /** Destination labels, per locale, exactly as `AC-02`/`AC-03` pinned them. */
    private val destinationLabels = mapOf(
        "en" to listOf("Home", "Activity", "Insights"),
        "it" to listOf("Home", "Attività", "Analisi"),
    )

    private val otherLanguageLabels = mapOf(
        "en" to listOf("Attività", "Analisi"),
        "it" to listOf("Activity", "Insights"),
    )

    /** The shell's only label-less action; its description is all a screen reader gets. */
    private val addActionDescriptions = mapOf(
        "en" to "Add transaction",
        "it" to "Aggiungi transazione",
    )

    @Test
    fun ac06_theShellAndRecoveryStateSurviveEveryLanguageWidthThemeAndTextSize() {
        val cell = mutableStateOf(cells.first())
        val host = mutableStateOf(HOSTS.first())

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
                    // The same content colour the production `Scaffold` supplies. #111 learned this
                    // the expensive way: a bare container sets none, `Text` falls back to black, and
                    // the dark cells read as a contrast defect the app does not have.
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.surface,
                        contentColor = MaterialTheme.colorScheme.onSurface,
                    ) {
                        when (host.value) {
                            SHELL -> PersonalFinanceNavHost(navController = rememberNavController())
                            else -> StoredDataUnavailableState(
                                message = stringForRecovery(),
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                }
            }
        }

        val index = StringBuilder("host,cell,locale,widthDp,theme,fontScale,png,semantics\n")
        val problems = mutableListOf<String>()

        HOSTS.forEach { hostId ->
            host.value = hostId
            cells.forEach { c ->
                cell.value = c
                rule.waitForIdle()
                val name = "$hostId--${c.id}"
                CaptureHarness.writePng(rule, dir, name)
                CaptureHarness.writeSemantics(rule, dir, name)
                index.append(
                    "$hostId,${c.id},${c.locale?.language ?: "en"},${c.widthDp},${c.theme}," +
                        "${c.fontScale},$name.png,$name.txt\n",
                )
                problems += inspect(hostId, c, name)
            }
        }
        File(dir, "index.csv").writeText(index.toString())

        // Every cell the index claims is on disk and non-empty. Asserted in the same test rather
        // than a second one, so nothing here depends on JUnit's method ordering.
        val rows = File(dir, "index.csv").readLines().drop(1).filter { it.isNotBlank() }
        assertEquals(HOSTS.size * cells.size, rows.size)
        rows.forEach { row ->
            val columns = row.split(",")
            assertTrue("missing ${columns[6]}", File(dir, columns[6]).length() > 0)
            assertTrue("missing ${columns[7]}", File(dir, columns[7]).length() > 0)
        }

        assertEquals(problems.joinToString("\n"), emptyList<String>(), problems)
    }

    /**
     * What a reviewer would be checking for, checked.
     *
     * Ellipsis is the one worth spelling out: `Text` truncates by drawing `…`, and the destination
     * labels are the place that matters — "Attività" and "Analisi" share a first letter, so a label
     * clipped to "A…" stops distinguishing two primary destinations, which is the specific failure
     * `AC-06` names.
     */
    private fun inspect(
        hostId: String,
        c: CaptureHarness.Cell,
        name: String,
    ): List<String> {
        val language = c.locale?.language ?: "en"
        val nodes = flatten(rule.onRoot(useUnmergedTree = true).fetchSemanticsNode())
        val texts = nodes.mapNotNull { node ->
            node.config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text }
        }
        val descriptions = nodes.mapNotNull {
            it.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
        }
        val problems = mutableListOf<String>()

        /**
         * The nodes #112 owns.
         *
         * Hosting the real shell means hosting whatever destination is behind it, so the tree also
         * holds Home's cards — and the first run of this matrix duly reported two of them
         * (`0 movimenti`, `0 giorni di fila`) collapsing to zero size at a 2.0 font scale. That is a
         * genuine large-text finding, and it is #88's card and #113's lane, not this contract's:
         * reporting it here would have made #112's gate fail on someone else's layout. It is
         * recorded on #112 as an out-of-scope observation with this cell as its evidence, and the
         * scope below is narrowed to the shell chrome and the recovery screen.
         */
        val foundationNodes = if (hostId == SHELL) {
            nodes.filter { node ->
                val text = node.config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text }
                val description = node.config
                    .getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
                text in destinationLabels.getValue(language) ||
                    description in addActionDescriptions.values
            }
        } else {
            nodes
        }

        // Clipping is read off the *layout result*, never off the text. `SemanticsProperties.Text`
        // carries the source string, so a label that renders as "Attivi…" still reports "Attività"
        // — scanning the semantics text for an ellipsis character is a filter that can never fire
        // and reads like an assertion.
        //
        // The signal is how many characters the last line actually shows, not
        // `TextLayoutResult.hasVisualOverflow`. That flag was tried first and reported *every*
        // label in every cell as clipped, including "Home" in English at a 1.0 font scale — it
        // answers a question about the measured constraints, not about whether a user lost
        // characters. `getLineEnd(visibleEnd = true)` answers the question being asked: if it stops
        // short of the string's length, glyphs were dropped and an ellipsis was drawn.
        var probed = 0
        foundationNodes.forEach { node ->
            val results = mutableListOf<TextLayoutResult>()
            val action = node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action
            if (action != null) {
                probed++
                action(results)
                results.firstOrNull()?.let { layout ->
                    val source = layout.layoutInput.text.text
                    val visible = layout.getLineEnd(layout.lineCount - 1, visibleEnd = true)
                    if (visible < source.length) {
                        problems += "$name: clipped \"$source\" to $visible of ${source.length} chars"
                    }
                    // For a destination label, wrapping is the failure this widget actually has.
                    // Proved by probe rather than assumed: a deliberately over-long Italian label
                    // at 200dp/2.0 was *not* ellipsised — Material 3's `NavigationBarItem` wrapped
                    // it onto three lines, pushing the icon out of the bar, with every character
                    // still present. So the truncation check above cannot fire here however narrow
                    // the bar gets, and a matrix relying on it alone would have reported a clean
                    // bill of health for a visibly broken bar.
                    if (hostId == SHELL &&
                        source in destinationLabels.getValue(language) &&
                        layout.lineCount > 1
                    ) {
                        problems += "$name: destination label \"$source\" wrapped onto " +
                            "${layout.lineCount} lines"
                    }
                }
            }
        }
        if (probed == 0) {
            problems += "$name: no foundation text node exposed GetTextLayoutResult, so clipping " +
                "went unchecked"
        }

        foundationNodes
            .filter { it.boundsInRoot.width <= 0f || it.boundsInRoot.height <= 0f }
            .forEach { problems += "$name: zero-size node ${it.config.getOrNull(SemanticsProperties.Text)}" }

        // No stale-language copy: the other language's labels must be absent, not merely
        // outnumbered. This is what catches a label resolved once and cached across a locale change.
        otherLanguageLabels.getValue(language).filter { it in texts }
            .forEach { problems += "$name: stale $it from the other language" }

        if (hostId == SHELL) {
            val expected = destinationLabels.getValue(language)
            // Every primary destination is present and still tells itself apart from its peers.
            expected.forEach { label ->
                if (label !in texts) problems += "$name: destination label \"$label\" missing"
            }
            if (expected.map { it.take(3) }.toSet().size != expected.size) {
                problems += "$name: destination labels are not distinguishable by their first 3 chars"
            }
            // The add action keeps its localized description at every size — the FAB has no
            // visible label, so a stale or missing description here is invisible to every text
            // check above and to every screenshot.
            if (addActionDescriptions.getValue(language) !in descriptions) {
                problems += "$name: the add action lost its localized content description"
            }
        } else {
            // The recovery screen's two required sentences — what failed and what was not deleted —
            // must both still be on screen; the reassurance is the one long-copy large-text would
            // push off first.
            if (texts.none { it.contains("eliminato") || it.contains("deleted") }) {
                problems += "$name: the recovery reassurance is not rendered"
            }
        }
        return problems
    }

    private fun flatten(node: SemanticsNode): List<SemanticsNode> =
        listOf(node) + node.children.flatMap { flatten(it) }

    @androidx.compose.runtime.Composable
    private fun stringForRecovery(): String = androidx.compose.ui.res.stringResource(
        com.rizzog99.personalfinancetracker.R.string.stored_data_unavailable_database,
    )

    private companion object {
        const val SHELL = "nav-shell"
        val HOSTS = listOf(SHELL, "startup-recovery")
    }
}
