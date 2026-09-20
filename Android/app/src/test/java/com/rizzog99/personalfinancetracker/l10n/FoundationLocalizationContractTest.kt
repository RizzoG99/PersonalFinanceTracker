package com.rizzog99.personalfinancetracker.l10n

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element

/**
 * Parity `M1-L10N-BASE` (#112) `AC-01` and `AC-05`, asserted against the resource files and the
 * production sources themselves rather than against a copy of them.
 *
 * The distinction this suite is built around: a hand-written list of expected keys stays green
 * forever, including after someone deletes the key from both locales or stops calling it. So the
 * inventory here is never the *only* authority. Three independent directions have to agree:
 *
 * 1. **Resources → inventory.** Every key in `values/strings.xml` whose name matches a foundation
 *    naming pattern must be inventoried. Adding a foundation-shaped key without wiring it in fails
 *    here — which is how `foundation_placeholder` sat unused from the scaffold commit onward.
 * 2. **Inventory → call sites.** Every inventoried key must be referenced from the production file
 *    that owns it. Renaming or removing a call site fails here.
 * 3. **Call sites → inventory.** Every `R.string.*` reference in the foundation source files must be
 *    inventoried. Adding a foundation string without declaring it fails here.
 *
 * Plus the plain parity checks: identical key sets across `values/` and `values-it/`, identical
 * format-placeholder signatures, and non-blank values in both.
 *
 * Deliberately excluded, with owners: every key belonging to a later feature capability. #112's
 * contract is the foundation shell and shared states; import/export copy is #79's, pulse and goal
 * copy is #88's, PIN and backup copy is #80's. They are neither inventoried nor asserted here.
 */
class FoundationLocalizationContractTest {

    // ------------------------------------------------------------------ the inventory

    /**
     * Source files whose entire user-facing copy is foundation copy. Both the `R.string.*` sweep
     * (direction 3) and the hard-coded-literal scan (`AC-05`) run over exactly these.
     *
     * `ActivityScreen.kt` is *not* here and must not be: it is two thousand lines of #79/#88 feature
     * copy that happens to also contain the foundation state branch. Its four foundation keys are
     * inventoried individually below, each tied to that file by direction 2.
     */
    private val foundationSources = listOf(
        "src/main/java/com/rizzog99/personalfinancetracker/MainActivity.kt",
        "src/main/java/com/rizzog99/personalfinancetracker/PersonalFinanceTrackerApp.kt",
        "src/main/java/com/rizzog99/personalfinancetracker/navigation/PersonalFinanceNavHost.kt",
        "src/main/java/com/rizzog99/personalfinancetracker/ui/components/AsyncState.kt",
    )

    private val activityScreen =
        "src/main/java/com/rizzog99/personalfinancetracker/features/activity/ActivityScreen.kt"

    private val activityViewModel =
        "src/main/java/com/rizzog99/personalfinancetracker/features/activity/ActivityViewModel.kt"

    /**
     * Foundation keys consumed from a file too broad to sweep wholesale, each paired with the file
     * that must reference it. The pairing is what keeps this list from being a curated fiction.
     */
    private val inventoriedElsewhere = mapOf(
        // The shared error state, rendered by Activity's production `when` (#111 AC-04).
        "error_state_message" to activityScreen,
        // First-run empty (#111 AC-02).
        "empty_state_title" to activityScreen,
        "empty_state_message" to activityScreen,
        // Filtered-to-nothing (#111 AC-03) and its recovery action.
        "no_matching_transactions" to activityScreen,
        "no_matching_transactions_message" to activityScreen,
        "clear_search_and_filters" to activityScreen,
        // The recoverable write-failure banner (#135, #111 `D-06`). Named in the ViewModel, which
        // holds the resource *id* rather than resolved text — that is #135's fix, and pinning the
        // call site here is what keeps a regression to `throwable.message` from going unnoticed.
        "activity_update_failed" to activityViewModel,
    )

    /**
     * Resource-key name shapes that mean "this is foundation copy".
     *
     * This is direction 1, and it is the tripwire the AC asks for: it reads the shipping resource
     * file, so a foundation key that exists but is inventoried nowhere fails the build instead of
     * quietly accumulating.
     */
    private val foundationKeyPatterns = listOf(
        Regex("^tab_"),
        Regex("^stored_data_unavailable"),
        Regex("^foundation_"),
        Regex("_state_(title|message)$"),
        Regex("^(loading|retry)$"),
        Regex("^no_matching_transactions"),
        Regex("^clear_search_and_filters$"),
    )

    // ------------------------------------------------------------------ resource loading

    private val moduleDir: File = generateSequence(File("").absoluteFile) { it.parentFile }
        .first { File(it, "src/main/res/values/strings.xml").isFile }

    private fun resources(qualifier: String): Map<String, Map<String, String>> {
        val file = File(moduleDir, "src/main/res/$qualifier/strings.xml")
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val out = LinkedHashMap<String, Map<String, String>>()
        val root = doc.documentElement.childNodes
        for (i in 0 until root.length) {
            val node = root.item(i) as? Element ?: continue
            val name = node.getAttribute("name")
            out[name] = when (node.tagName) {
                "string" -> mapOf("" to node.textContent)
                "plurals" -> node.childElements().associate { it.getAttribute("quantity") to it.textContent }
                "string-array" -> node.childElements().withIndex().associate { (n, e) -> "$n" to e.textContent }
                else -> continue
            }
        }
        return out
    }

    private fun Element.childElements(): List<Element> =
        (0 until childNodes.length).mapNotNull { childNodes.item(it) as? Element }

    private fun source(path: String): String = File(moduleDir, path).readText()

    private val en by lazy { resources("values") }
    private val it by lazy { resources("values-it") }

    /** Every `R.string.x` mentioned anywhere in the foundation sources. */
    private val referencedInFoundationSources: Set<String> by lazy {
        foundationSources.flatMap { path ->
            Regex("""R\.string\.(\w+)""").findAll(source(path)).map { it.groupValues[1] }
        }.toSet()
    }

    private val inventory: Set<String> by lazy {
        referencedInFoundationSources + inventoriedElsewhere.keys
    }

    // ------------------------------------------------------------------ AC-01

    @Test
    fun ac01_defaultAndItalianDeclareTheSameKeys() {
        assertEquals("keys missing from values-it/", emptySet<String>(), en.keys - it.keys)
        assertEquals("keys only in values-it/", emptySet<String>(), it.keys - en.keys)
    }

    @Test
    fun ac01_everyInventoriedFoundationKeyExistsAndIsNonBlankInBothLocales() {
        val problems = inventory.sorted().mapNotNull { key ->
            val e = en[key]?.values?.singleOrNull()
            val i = it[key]?.values?.singleOrNull()
            when {
                e == null -> "$key: absent from values/strings.xml"
                i == null -> "$key: absent from values-it/strings.xml"
                e.isBlank() -> "$key: blank in values/"
                i.isBlank() -> "$key: blank in values-it/"
                else -> null
            }
        }
        assertEquals(emptyList<String>(), problems)
    }

    @Test
    fun ac01_formatPlaceholdersAgreeAcrossLocales() {
        val problems = mutableListOf<String>()
        en.forEach { (key, variants) ->
            variants.forEach { (variant, value) ->
                val other = it[key]?.get(variant)
                if (other == null) {
                    problems += "$key[$variant]: no Italian counterpart"
                } else if (placeholderSignature(value) != placeholderSignature(other)) {
                    problems += "$key[$variant]: ${placeholderSignature(value)} vs " +
                        placeholderSignature(other)
                }
            }
        }
        assertEquals(emptyList<String>(), problems)
    }

    /**
     * Direction 1. A foundation-shaped key that nothing inventories is an obsolete key by
     * definition — the shell, the gates and the shared states are the only things that use this
     * naming, so a match here with no inventory entry means the copy is stranded.
     */
    @Test
    fun ac01_noFoundationShapedResourceKeyIsStrandedOutsideTheInventory() {
        val stranded = en.keys
            .filter { key -> foundationKeyPatterns.any { it.containsMatchIn(key) } }
            .filterNot { it in inventory }
            .sorted()
        assertEquals(
            "foundation-shaped resource keys with no production consumer — delete them or " +
                "inventory them",
            emptyList<String>(),
            stranded,
        )
    }

    /** Direction 2. The list above is only worth anything if the call sites it names are real. */
    @Test
    fun ac01_everyKeyInventoriedElsewhereIsActuallyReferencedByItsNamedCallSite() {
        val missing = inventoriedElsewhere.filterNot { (key, path) ->
            source(path).contains("R.string.$key")
        }
        assertEquals(emptyMap<String, String>(), missing)
    }

    /**
     * Direction 3, and the check that keeps the inventory from being editable by hand alone: the
     * foundation sources define it, so a new `R.string.*` there is inventoried whether or not
     * anybody remembered to write it down.
     */
    @Test
    fun ac01_everyFoundationSourceReferenceResolvesToADeclaredResource() {
        val unresolved = (referencedInFoundationSources - en.keys).sorted()
        assertEquals(emptyList<String>(), unresolved)
        assertTrue(
            "the foundation source sweep found nothing — the paths are probably wrong",
            referencedInFoundationSources.size > 10,
        )
    }

    // ------------------------------------------------------------------ AC-05

    /**
     * No user-facing literal in foundation Compose code.
     *
     * Scoped by *argument position*, not by literal: a string becomes copy when it is handed to
     * something that renders or announces it. Route names, test tags, log keys, database ids and
     * format tokens are all ordinary literals in other positions and stay legal — see
     * [ac05_theScanSeparatesUserFacingCopyFromOrdinaryLiterals], which proves the separation on a
     * sample containing one of each.
     */
    @Test
    fun ac05_noFoundationComposeCodeContainsHardCodedUserFacingCopy() {
        val findings = foundationSources.flatMap { path ->
            hardCodedCopy(source(path)).map { "$path: $it" }
        }
        assertEquals(emptyList<String>(), findings)
    }

    @Test
    fun ac05_theScanSeparatesUserFacingCopyFromOrdinaryLiterals() {
        val sample = """
            // A comment mentioning Text("not a finding") must not count.
            /** Nor KDoc saying contentDescription = "still not a finding". */
            data object Home : MainDestination("home", R.string.tab_home)
            private const val TAG = "PersonalFinanceApp"
            Modifier.testTag("nav-shell")
            val pattern = "yyyy-MM-dd"
            room.query("SELECT * FROM transactions")
            Log.d("startup", "probe finished")
            Text(stringResource(R.string.tab_home))
            Icon(contentDescription = stringResource(R.string.add_transaction))
            Icon(contentDescription = null)
            Text("Add transaction")
        """.trimIndent()

        assertEquals(listOf("""Text("Add transaction")"""), hardCodedCopy(sample))
    }

    // ------------------------------------------------------------------ helpers

    /**
     * `%1${'$'}s`-style and bare `%s`-style placeholders, reduced to (position, conversion) pairs.
     * Reordering them in one locale, changing `%d` to `%s`, or dropping one changes the signature.
     */
    private fun placeholderSignature(value: String): List<Pair<Int, Char>> =
        Regex("""%(?:(\d+)\$)?[-#+ 0,(]*\d*(?:\.\d+)?([a-zA-Z%])""")
            .findAll(value)
            .filter { it.groupValues[2] != "%" }
            .mapIndexed { index, match ->
                (match.groupValues[1].toIntOrNull() ?: (index + 1)) to match.groupValues[2].single()
            }
            .sortedBy { it.first }
            .toList()

    /**
     * Argument positions that put a string in front of a user or a screen reader.
     *
     * A literal is copy because of where it is handed in, not because it is a literal. Everything
     * else stays legal: `MainDestination("home", …)` in the scanned nav host is a route name,
     * `Modifier.testTag("…")` is a test hook, `"yyyy-MM-dd"` is a format token, an SQL string is a
     * query. Banning every literal instead would have flagged all four and taught the next person
     * to suppress the check.
     */
    private val copyPositions = listOf(
        "Text" to Regex("""\bText\s*\(\s*"([^"]*)""""),
        "text" to Regex("""\btext\s*=\s*"([^"]*)""""),
        "contentDescription" to Regex("""\bcontentDescription\s*=\s*"([^"]*)""""),
        "label" to Regex("""\blabel\s*=\s*"([^"]*)""""),
        "title" to Regex("""\btitle\s*=\s*"([^"]*)""""),
        "message" to Regex("""\bmessage\s*=\s*"([^"]*)""""),
        "placeholder" to Regex("""\bplaceholder\s*=\s*"([^"]*)""""),
    )

    private fun hardCodedCopy(source: String): List<String> {
        val code = source
            .replace(Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL), "")
            .replace(Regex("""//[^\n]*"""), "")
        return copyPositions.flatMap { (position, pattern) ->
            pattern.findAll(code).map { match ->
                val literal = match.groupValues[1]
                if (position == "Text") """Text("$literal")""" else """$position = "$literal""""
            }
        }
    }
}
