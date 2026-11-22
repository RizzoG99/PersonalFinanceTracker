package com.rizzog99.personalfinancetracker.l10n

import android.app.LocaleManager
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.ACTIVITY_SEARCH_TAG
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import java.math.BigDecimal
import java.time.Instant
import java.util.Locale
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #291 on the production path: a built-in category reads in the app language after a real per-app
 * locale switch (`LocaleManager`, as [FoundationLocaleRecreationTest]), search finds it by its
 * translation, and the edit sheet keeps its stored key when saved unchanged.
 */
@RunWith(AndroidJUnit4::class)
class CategoryLocalizationFlowTest {

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.pinLockRepository.clearPin()
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                val groceries = groceries()
                app.transactionRepository.insertBatch(
                    listOf(
                        FinanceTransaction(
                            id = "t-groceries", timestamp = Instant.now(), amount = BigDecimal("-12.50"), note = "",
                            categoryLabel = groceries.name, categoryId = groceries.id, currencyCode = "EUR",
                            goalId = null, recurrenceRuleId = null,
                        ),
                    ),
                )
            }
        })
        .around(rule)

    private val app: PersonalFinanceApplication
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
            as PersonalFinanceApplication

    private suspend fun groceries() =
        app.categoryRepository.observeAll().first().single { it.name == "Groceries" && it.type == TransactionType.EXPENSE }

    @Before
    fun needsPerAppLocales() {
        assumeTrue("LocaleManager per-app locales need API 33+", Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
        rule.waitForIdle()
    }

    @After
    fun restore() {
        setAppLocale(null)
        runBlocking { app.database.clearAllTables() }
    }

    private fun setAppLocale(locale: Locale?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSystemService(LocaleManager::class.java).applicationLocales =
            locale?.let { LocaleList(it) } ?: LocaleList.getEmptyLocaleList()
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        rule.waitForIdle()
    }

    private fun italian(id: Int): String {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val configuration = Configuration(base.resources.configuration).apply { setLocales(LocaleList(Locale.ITALIAN)) }
        return base.createConfigurationContext(configuration).getString(id)
    }

    private fun waitForText(text: String) = rule.waitUntil(20_000) {
        rule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()
    }

    @Test
    fun ac01_italianActivityShowsAndFindsSpesa() {
        val it = NavShellMarkers(Locale.ITALIAN)
        setAppLocale(Locale.ITALIAN)
        with(it) { rule.selectTab(it.activityTab) }

        waitForText("Spesa")
        rule.onAllNodesWithText("Groceries", substring = true).assertCountIsZero()

        rule.onNode(hasTestTag(ACTIVITY_SEARCH_TAG)).performTextInput("spesa")
        rule.waitForIdle()
        // The row, not the search field: the field holds lower-case "spesa", the row "Spesa".
        waitForText("Spesa")
    }

    @Test
    fun ac02_editSheetShowsSpesaAndKeepsTheKeyWhenUnchanged() {
        setAppLocale(Locale.ITALIAN)
        openGroceriesEditor()
        rule.onNode(hasSetTextAction() and hasText("Spesa")).assertExists()
        rule.onNodeWithText(italian(R.string.save)).performClick()
        rule.waitForIdle()
        assertEquals("Groceries", runBlocking { groceries() }.name)

        rule.onNodeWithText("Spesa").performClick()
        rule.onNode(hasSetTextAction() and hasText("Spesa")).performTextReplacement("Alimentari")
        rule.onNodeWithText(italian(R.string.save)).performClick()
        rule.waitUntil(20_000) {
            runBlocking { app.categoryRepository.observeAll().first() }.any { it.name == "Alimentari" }
        }
        setAppLocale(Locale.ENGLISH)
        waitForText("Alimentari")
    }

    private fun openGroceriesEditor() {
        rule.onNode(hasContentDescription(italian(R.string.settings_title))).performClick()
        rule.onNodeWithText(italian(R.string.categories)).performClick()
        waitForText("Spesa")
        rule.onNodeWithText("Spesa").performClick()
        rule.waitForIdle()
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteractionCollection.assertCountIsZero() =
        assertEquals(0, fetchSemanticsNodes().size)
}
