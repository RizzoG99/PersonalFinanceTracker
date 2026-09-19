package com.rizzog99.personalfinancetracker.features.activity

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.SearchDateRange
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionSearch
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityFilterSelectionTest {
    private val zoneId = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(Instant.parse("2026-09-19T10:00:00Z"), zoneId)

    @Test
    fun `AC-02 changing or clearing type clears the single category selection`() {
        val initial = ActivityFilterSelection(
            filters = TransactionFilters(
                type = TransactionTypeFilter.INCOME,
                category = "Gift",
            ),
        )

        assertNull(initial.withType(TransactionTypeFilter.EXPENSE).filters.category)
        assertNull(initial.withType(TransactionTypeFilter.ALL).filters.category)
        assertEquals("Gift", initial.withType(TransactionTypeFilter.INCOME).filters.category)
    }

    @Test
    fun `AC-02 category options come from the typed current result set`() {
        val transactions = listOf(
            transaction("income-gift", "100", "Gift", "September gift"),
            transaction("income-salary", "1200", "Salary", "September salary"),
            transaction("expense-gift", "-20", "Gift", "September gift"),
            transaction("older-income", "50", "Older", "August gift", "2026-08-01T10:00:00Z"),
        )
        val selection = ActivityFilterSelection(
            searchText = "September",
            filters = TransactionFilters(
                type = TransactionTypeFilter.INCOME,
                dateRange = SearchDateRange.ThisMonth,
            ),
        )

        assertEquals(
            listOf("Salary", "Gift"),
            availableActivityCategoryLabels(transactions, selection, zoneId, clock),
        )
        assertEquals(
            emptyList<String>(),
            availableActivityCategoryLabels(
                transactions,
                selection.withType(TransactionTypeFilter.ALL),
                zoneId,
                clock,
            ),
        )
    }

    @Test
    fun `AC-05 sheet validation rejects negative and reversed bounds without rejecting valid edge cases`() {
        val negativeMinimum = validateActivityAmountRange("-0.01", "")
        assertFalse(negativeMinimum.isValid)
        assertTrue(negativeMinimum.minimumHasError)
        assertFalse(negativeMinimum.maximumHasError)
        assertNull(
            resolveActivityFilterDraft(
                transactions = emptyList(),
                searchText = "",
                appliedFilters = TransactionFilters(type = TransactionTypeFilter.INCOME),
                selectedCategory = null,
                selectedDateRange = null,
                amountRange = negativeMinimum,
                recurringOnly = false,
                zoneId = zoneId,
                clock = clock,
            ),
        )

        val negativeMaximum = validateActivityAmountRange("", "-0.01")
        assertFalse(negativeMaximum.isValid)
        assertFalse(negativeMaximum.minimumHasError)
        assertTrue(negativeMaximum.maximumHasError)

        val reversed = validateActivityAmountRange("10", "9.99")
        assertFalse(reversed.isValid)
        assertTrue(reversed.minimumHasError)
        assertTrue(reversed.maximumHasError)

        listOf(
            "" to "",
            "0" to "0",
            "10" to "",
            "" to "10",
            "10" to "10",
            "10,50" to "10,50",
        ).forEach { (minimum, maximum) ->
            assertTrue("Expected $minimum to $maximum to be valid", validateActivityAmountRange(minimum, maximum).isValid)
        }
        assertEquals(BigDecimal("10.50"), validateActivityAmountRange("10,50", "").minimum)
    }

    @Test
    fun `AC-02 and AC-07 staged date amount and recurring filters refresh category choices`() {
        val transactions = listOf(
            transaction("salary", "1200", "Salary", "Current recurring salary", recurrenceRuleId = "salary-rule"),
            transaction("gift", "100", "Gift", "Current gift"),
            transaction("bonus", "500", "Bonus", "Older recurring bonus", "2026-08-01T10:00:00Z", "bonus-rule"),
        )
        val appliedFilters = TransactionFilters(type = TransactionTypeFilter.INCOME)

        fun draft(
            dateRange: SearchDateRange? = null,
            minimum: String = "",
            recurringOnly: Boolean = false,
        ) = requireNotNull(
            resolveActivityFilterDraft(
                transactions = transactions,
                searchText = "",
                appliedFilters = appliedFilters,
                selectedCategory = null,
                selectedDateRange = dateRange,
                amountRange = validateActivityAmountRange(minimum, ""),
                recurringOnly = recurringOnly,
                zoneId = zoneId,
                clock = clock,
            ),
        )

        assertEquals(listOf("Salary", "Gift"), draft(dateRange = SearchDateRange.ThisMonth).categoryLabels)
        assertEquals(listOf("Salary"), draft(minimum = "1000").categoryLabels)
        assertEquals(listOf("Salary", "Bonus"), draft(recurringOnly = true).categoryLabels)
    }

    @Test
    fun `AC-02 and AC-07 invalid staged category is cleared before apply while a valid one is preserved`() {
        val transactions = listOf(
            transaction("salary", "1200", "Salary", "Current salary"),
            transaction("bonus", "500", "Bonus", "Older bonus", "2026-08-01T10:00:00Z"),
        )
        val appliedFilters = TransactionFilters(type = TransactionTypeFilter.INCOME, category = "Bonus")

        fun draft(selectedCategory: String) = requireNotNull(
            resolveActivityFilterDraft(
                transactions = transactions,
                searchText = "",
                appliedFilters = appliedFilters,
                selectedCategory = selectedCategory,
                selectedDateRange = SearchDateRange.ThisMonth,
                amountRange = validateActivityAmountRange("", ""),
                recurringOnly = false,
                zoneId = zoneId,
                clock = clock,
            ),
        )

        val invalidated = draft("Bonus")
        assertEquals(listOf("Salary"), invalidated.categoryLabels)
        assertTrue(invalidated.categoryWasInvalidated)
        assertNull(invalidated.filters.category)

        val preserved = draft("Salary")
        assertFalse(preserved.categoryWasInvalidated)
        assertEquals("Salary", preserved.filters.category)
    }

    @Test
    fun `AC-07 filter-sheet clear preserves search and clears structured filters`() {
        val selection = populatedSelection().clearStructuredFilters()

        assertEquals("coffee", selection.searchText)
        assertEquals(TransactionFilters(), selection.filters)
    }

    @Test
    fun `AC-09 no-results recovery clears search and structured filters`() {
        assertEquals(ActivityFilterSelection(), populatedSelection().clearSearchAndFilters())
    }

    @Test
    fun `AC-08 summary totals use exactly the filtered visible dataset`() {
        val transactions = listOf(
            transaction("trip-income", "100.00", "Refund", "Rome trip"),
            transaction("trip-expense", "-25.50", "Travel", "Rome trip"),
            transaction("other-income", "50.00", "Gift", "Birthday"),
            transaction("trip-zero", "0", "Other", "Rome trip"),
        )
        val visibleTransactions = TransactionSearch.filter(
            transactions = transactions,
            searchText = "trip",
            filters = TransactionFilters(),
            zoneId = zoneId,
            clock = clock,
        )

        assertEquals(listOf("trip-income", "trip-expense", "trip-zero"), visibleTransactions.map { it.id })
        assertEquals(
            ActivitySummaryTotals(income = BigDecimal("100.00"), expenses = BigDecimal("25.50")),
            calculateActivitySummaryTotals(visibleTransactions),
        )
    }

    private fun populatedSelection() = ActivityFilterSelection(
        searchText = "coffee",
        filters = TransactionFilters(
            type = TransactionTypeFilter.EXPENSE,
            category = "Coffee",
            recurringOnly = true,
        ),
    )

    private fun transaction(
        id: String,
        amount: String,
        category: String,
        note: String,
        timestamp: String = "2026-09-10T10:00:00Z",
        recurrenceRuleId: String? = null,
    ) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse(timestamp),
        amount = BigDecimal(amount),
        note = note,
        categoryLabel = category,
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = recurrenceRuleId,
    )
}
