package com.rizzog99.personalfinancetracker.l10n

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.local.StartupFailure
import com.rizzog99.personalfinancetracker.features.activity.ActivityContent
import com.rizzog99.personalfinancetracker.features.activity.ActivityUiState
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.components.StoredDataUnavailableState
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Parity `M1-L10N-BASE` (#112) `AC-02` and `AC-03`: the foundation copy a user actually reads, in
 * English and in Italian, rendered by the production composables.
 *
 * Why this exists next to #110's and #111's suites rather than inside them: those audits proved
 * *structure*. `NavShellMarkers` looks tabs up through `R.string.tab_home`, so it asserts "the shell
 * shows whatever that key holds" — true no matter what the key holds, including an empty string or
 * English on an Italian device. #111's matrix rendered Italian cells but asserted semantics, not
 * words. The expectations here are written out literally instead, so the reviewed copy is what the
 * build checks. The one existing exception is reused rather than repeated:
 * `NavShellGraphTest.ac06_italianLabelsIdentifyAllThreeDestinations` already pins the three Italian
 * destination labels, and this suite adds the English side and everything else.
 *
 * Hosts are production: [PersonalFinanceNavHost] with the controller seam #110 established,
 * [ActivityContent] (`internal` for exactly this since #111), and [StoredDataUnavailableState] as
 * `PersonalFinanceTrackerApp` renders it.
 *
 * Out of scope on purpose: the four *secondary* destination labels the shell references
 * (`budgets_title`, `category_settings_title`, `import_export_title`, `scan_categories_title`).
 * They are inventoried and parity-checked by `FoundationLocalizationContractTest`, but their wording
 * belongs to the feature capabilities that own those screens (#79, #95, #97), not to #112.
 */
@RunWith(AndroidJUnit4::class)
class FoundationLocalizationEvidenceTest {

    @get:Rule
    val rule = createComposeRule()

    /** Reviewed copy, written out rather than read back from the resource it is checking. */
    private data class Copy(val en: String, val it: String) {
        fun forLocale(locale: Locale) = if (locale.language == "it") it else en
    }

    private val tabHome = Copy(en = "Home", it = "Home")
    private val tabActivity = Copy(en = "Activity", it = "Attività")
    private val tabInsights = Copy(en = "Insights", it = "Analisi")
    private val addTransaction = Copy(en = "Add transaction", it = "Aggiungi transazione")

    private val loading = Copy(
        en = "Loading your finances",
        it = "Caricamento delle tue finanze",
    )
    private val emptyTitle = Copy(en = "Nothing here yet", it = "Non c’è ancora nulla")
    private val emptyMessage = Copy(
        en = "Add your first transaction to start tracking your finances.",
        it = "Aggiungi la tua prima transazione per iniziare a tenere traccia delle finanze.",
    )
    private val noResultsTitle = Copy(
        en = "No matching transactions",
        it = "Nessuna transazione corrispondente",
    )
    private val noResultsMessage = Copy(
        en = "Try another search or clear your filters.",
        it = "Prova un’altra ricerca o cancella i filtri.",
    )
    private val clearFilters = Copy(
        en = "Clear search and filters",
        it = "Cancella ricerca e filtri",
    )
    private val errorTitle = Copy(en = "Something went wrong", it = "Si è verificato un problema")
    private val errorMessage = Copy(
        en = "We couldn't load your finances just now. Nothing has been deleted — your data is " +
            "still on this device.",
        it = "Non siamo riusciti a caricare le tue finanze in questo momento. Non è stato " +
            "eliminato nulla: i tuoi dati sono ancora su questo dispositivo.",
    )
    private val retry = Copy(en = "Try again", it = "Riprova")

    private val recoveryTitle = Copy(
        en = "Your saved data couldn't be opened",
        it = "Impossibile aprire i tuoi dati",
    )
    private val recoveryDatabase = Copy(
        en = "The file holding your transactions, goals and history is damaged, so the app can't " +
            "show them.",
        it = "Il file che contiene le tue transazioni, i tuoi obiettivi e lo storico è " +
            "danneggiato, quindi l'app non può mostrarli.",
    )
    private val recoveryPreferences = Copy(
        en = "The file holding your settings is damaged, so the app can't apply them.",
        it = "Il file che contiene le tue impostazioni è danneggiato, quindi l'app non può " +
            "applicarle.",
    )
    private val recoveryReassurance = Copy(
        en = "Nothing has been deleted. Your file is still on this device exactly as it was. Try " +
            "reopening the app, or restore a backup.",
        it = "Non è stato eliminato nulla. Il tuo file è ancora su questo dispositivo, " +
            "esattamente com'era. Prova a riaprire l'app oppure ripristina un backup.",
    )

    // ------------------------------------------------------------------ AC-02 / AC-03 shell

    @Test
    fun ac02_theNavigationShellRendersEnglishDestinationLabelsAndTheAddAction() =
        assertShell(Locale.ENGLISH)

    @Test
    fun ac03_theNavigationShellRendersItalianDestinationLabelsAndTheAddAction() =
        assertShell(Locale.ITALIAN)

    private fun assertShell(locale: Locale) {
        hostShell(locale)
        listOf(tabHome, tabActivity, tabInsights).forEach {
            rule.onNode(hasText(it.forLocale(locale))).assertIsDisplayed()
        }
        // The FAB carries no visible label, so its content description is the only thing a screen
        // reader has — and a stale one here is invisible to every text assertion above.
        rule.onNodeWithContentDescription(addTransaction.forLocale(locale)).assertIsDisplayed()
    }

    // ------------------------------------------------------------------ AC-02 / AC-03 recovery

    @Test
    fun ac02_theStartupRecoveryStateRendersEnglish() = assertRecovery(Locale.ENGLISH)

    @Test
    fun ac03_theStartupRecoveryStateRendersItalian() = assertRecovery(Locale.ITALIAN)

    /**
     * Both failure messages, because `PersonalFinanceTrackerApp` picks between them on
     * [StartupFailure] and a user whose settings file is damaged must not be told their
     * transactions are gone. Which branch picks which is #109's; that both read correctly in both
     * languages is #112's.
     */
    private fun assertRecovery(locale: Locale) {
        val failure = mutableStateOf(StartupFailure.DATABASE)
        hostLocalized(locale) {
            // `stringResource`, not the test's own expectation handed back to itself. Passing
            // `recoveryDatabase.forLocale(locale)` in here and asserting it came out would have
            // gone green with the Italian key deleted — the assertion would have been reading the
            // literal three lines above it. This mirrors `PersonalFinanceTrackerApp`'s own `when`.
            StoredDataUnavailableState(
                message = stringResource(
                    when (failure.value) {
                        StartupFailure.PREFERENCES -> R.string.stored_data_unavailable_preferences
                        else -> R.string.stored_data_unavailable_database
                    },
                ),
                modifier = Modifier.fillMaxSize(),
            )
        }
        rule.onNodeWithText(recoveryTitle.forLocale(locale)).assertIsDisplayed()
        rule.onNodeWithText(recoveryDatabase.forLocale(locale)).assertIsDisplayed()
        rule.onNodeWithText(recoveryReassurance.forLocale(locale)).assertIsDisplayed()

        failure.value = StartupFailure.PREFERENCES
        rule.waitForIdle()
        rule.onNodeWithText(recoveryPreferences.forLocale(locale)).assertIsDisplayed()
    }

    // ------------------------------------------------------------------ AC-02 / AC-03 states

    @Test
    fun ac02_everySharedStateRendersItsEnglishCopyAndAction() = assertStates(Locale.ENGLISH)

    @Test
    fun ac03_everySharedStateRendersItsItalianCopyAndAction() = assertStates(Locale.ITALIAN)

    /**
     * Loading, first-run empty, no-results, error and retry-in-progress, driven through the
     * production `when` in [ActivityContent] rather than by calling each primitive directly — the
     * branch that picks the state is as much a part of "the right copy appeared" as the copy is.
     */
    private fun assertStates(locale: Locale) {
        val state = mutableStateOf(ActivityUiState(isLoading = true))
        hostLocalized(locale) {
            ActivityContent(
                state = state.value,
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

        // Loading.
        rule.onNodeWithText(loading.forLocale(locale)).assertIsDisplayed()

        // First-run empty, with its own action verb.
        show(state, ActivityUiState(isLoading = false))
        rule.onNodeWithText(emptyTitle.forLocale(locale)).assertIsDisplayed()
        rule.onNodeWithText(emptyMessage.forLocale(locale)).assertIsDisplayed()
        rule.onNode(hasText(addTransaction.forLocale(locale)) and hasClickAction())
            .performScrollTo()
            .assertIsDisplayed()

        // No results: different copy and a different verb, which is the distinction #111 AC-03
        // made load-bearing and this suite has to keep in both languages.
        show(
            state,
            ActivityUiState(
                isLoading = false,
                allTransactions = listOf(sample()),
                visibleTransactions = emptyList(),
                searchText = "zzzz",
            ),
        )
        rule.onNodeWithText(noResultsTitle.forLocale(locale)).assertIsDisplayed()
        rule.onNodeWithText(noResultsMessage.forLocale(locale)).assertIsDisplayed()
        rule.onNode(hasText(clearFilters.forLocale(locale)) and hasClickAction())
            .performScrollTo()
            .assertIsDisplayed()

        // Recoverable error, and the retry action.
        show(state, ActivityUiState(isLoading = false, isError = true))
        rule.onNodeWithText(errorTitle.forLocale(locale)).assertIsDisplayed()
        rule.onNodeWithText(errorMessage.forLocale(locale)).assertIsDisplayed()
        rule.onNode(hasText(retry.forLocale(locale)) and hasClickAction())
            .performScrollTo()
            .assertIsDisplayed()

        // Retry in progress: the loading copy again, reached by re-entering loading from error.
        show(state, ActivityUiState(isLoading = true, isError = false))
        rule.onNodeWithText(loading.forLocale(locale)).assertIsDisplayed()
    }

    // ------------------------------------------------------------------ hosting

    private fun show(state: MutableState<ActivityUiState>, next: ActivityUiState) {
        state.value = next
        rule.waitForIdle()
    }

    private fun hostShell(locale: Locale) {
        lateinit var navController: NavHostController
        hostLocalized(locale) {
            navController = rememberNavController()
            PersonalFinanceNavHost(navController = navController)
        }
    }

    private fun hostLocalized(locale: Locale, content: @Composable () -> Unit) {
        rule.setContent {
            val context = localeContext(LocalContext.current, locale)
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides Configuration(context.resources.configuration),
            ) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.surface,
                        contentColor = MaterialTheme.colorScheme.onSurface,
                    ) { content() }
                }
            }
        }
        rule.waitForIdle()
    }

    /**
     * Italian resources over the *same* context chain — the wrapper matters, and #110 records why:
     * a bare `createConfigurationContext` is not on the chain
     * `LocalActivityResultRegistryOwner` walks, so Home's photo-picker launcher throws before a
     * single label can be read.
     */
    private fun localeContext(base: Context, locale: Locale): Context {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(locale)) },
        )
        return object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    }

    private fun sample() = FinanceTransaction(
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
