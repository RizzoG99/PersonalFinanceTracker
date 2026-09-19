package com.rizzog99.personalfinancetracker.features.activity

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.SearchDateRange
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionFilters
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
    fun `AC-07 filter-sheet clear preserves search and clears structured filters`() {
        val selection = populatedSelection().clearStructuredFilters()

        assertEquals("coffee", selection.searchText)
        assertEquals(TransactionFilters(), selection.filters)
    }

    @Test
    fun `AC-09 no-results recovery clears search and structured filters`() {
        assertEquals(ActivityFilterSelection(), populatedSelection().clearSearchAndFilters())
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
    ) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse(timestamp),
        amount = BigDecimal(amount),
        note = note,
        categoryLabel = category,
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = null,
    )
}
