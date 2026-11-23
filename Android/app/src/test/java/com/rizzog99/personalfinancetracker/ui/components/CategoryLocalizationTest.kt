package com.rizzog99.personalfinancetracker.ui.components

import com.rizzog99.personalfinancetracker.domain.category.CategoryNameValidator
import com.rizzog99.personalfinancetracker.domain.category.DefaultCategories
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.displayTitle
import com.rizzog99.personalfinancetracker.features.categories.CategoryNameError
import com.rizzog99.personalfinancetracker.features.categories.categoryNameError
import com.rizzog99.personalfinancetracker.features.categories.editorStoredName
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionSearch
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import com.rizzog99.personalfinancetracker.features.activity.ActivityFilterSelection
import com.rizzog99.personalfinancetracker.features.activity.availableActivityCategoryLabels
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** #291: built-in names are translated for display and search, and an untouched edit keeps the key. */
class CategoryLocalizationTest {
    private val italian = mapOf("Groceries" to "Spesa", "Healthcare" to "Sanità")
    private val rows = listOf(
        row("g", "-12.50", "Groceries"),
        row("h", "-30.00", "Healthcare"),
        row("p", "-40.00", "Palestra"),
    )

    @Test
    fun everyDefaultHasATranslation() {
        assertEquals(DefaultCategories.all.map { it.name }.toSet(), builtInCategoryNames.keys)
    }

    @Test
    fun ac01_searchMatchesStoredKeyAndTranslationIgnoringAccents() {
        fun search(query: String) = TransactionSearch.filter(rows, query, TransactionFilters(), ZoneOffset.UTC, categoryNames = italian).map { it.id }
        assertEquals(listOf("g"), search("spesa"))
        assertEquals(listOf("g"), search("GROCERIES"))
        assertEquals(listOf("h"), search("sanita"))
        assertEquals(listOf("p"), search("palestra"))
        assertEquals(emptyList<String>(), search("altro"))
    }

    @Test
    fun ac01_italianSearchKeepsTheCategoryInTheFilterSheet() {
        val labels = availableActivityCategoryLabels(
            rows,
            ActivityFilterSelection(searchText = "spesa").withType(TransactionTypeFilter.EXPENSE),
            ZoneOffset.UTC,
            categoryNames = italian,
        )
        assertEquals(listOf("Groceries"), labels)
    }

    @Test
    fun ac02_unchangedTranslatedNameKeepsKey() {
        assertNull(CategoryNameValidator.renamedName(stored = "Groceries", edited = " Spesa ", shown = "Spesa"))
        assertEquals("Alimentari", CategoryNameValidator.renamedName(stored = "Groceries", edited = "Alimentari", shown = "Spesa"))
        assertNull(CategoryNameValidator.renamedName(stored = "Palestra", edited = "Palestra", shown = "Palestra"))
    }

    /** An untouched "Spesa" is validated as "Groceries", so a custom "Spesa" cannot block its Save. */
    @Test
    fun ac02_untouchedBuiltInDoesNotCollideWithACustomNamedLikeItsTranslation() {
        val groceries = FinanceCategory("g", "Groceries", "cart", TransactionType.EXPENSE, "categoryGreen", null, "EUR")
        val custom = groceries.copy(id = "s", name = "Spesa")
        val stored = editorStoredName(groceries, edited = "Spesa", shown = "Spesa")
        assertEquals("Groceries", stored)
        assertNull(categoryNameError(stored, TransactionType.EXPENSE, groceries.id, listOf(groceries, custom), showBlankError = true))
        // Renaming it onto the custom name is still a duplicate.
        assertEquals(CategoryNameError.DUPLICATE, categoryNameError(editorStoredName(groceries, "Spesa ", "Groceries"), TransactionType.EXPENSE, groceries.id, listOf(groceries, custom), true))
    }

    /** A recurring rule's own note is shown as typed; only the category fallback is translated. */
    @Test
    fun ac01_recurringTitleTranslatesOnlyTheCategoryFallback() {
        fun rule(note: String) = RecurrenceRule(
            id = "r", frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = Instant.EPOCH, endDate = null,
            lastMaterializedDate = null, amount = BigDecimal("-9.99"), note = note, categoryLabel = "Groceries",
            categoryId = null, currencyCode = "EUR", goalId = null,
        )
        val names = mapOf("Groceries" to "Spesa", "Salary" to "Stipendio")
        assertEquals("Spesa", rule("").displayTitle(names))
        assertEquals("Salary", rule("Salary").displayTitle(names))
    }

    private fun row(id: String, amount: String, label: String) = FinanceTransaction(
        id = id, timestamp = Instant.parse("2026-10-15T09:00:00Z"), amount = BigDecimal(amount), note = "",
        categoryLabel = label, categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
    )
}
