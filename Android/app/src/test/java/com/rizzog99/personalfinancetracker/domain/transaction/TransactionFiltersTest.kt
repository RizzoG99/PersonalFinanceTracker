package com.rizzog99.personalfinancetracker.domain.transaction

import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

class TransactionFiltersTest {
    private val zoneId = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(Instant.parse("2026-09-04T10:00:00Z"), zoneId)
    private val transactions = listOf(
        transaction("income", "2026-09-01T09:00:00Z", "1200.00", "September salary", "Salary"),
        transaction("expense", "2026-09-02T09:00:00Z", "-19.99", "Morning coffee", "Coffee & Drinks"),
        transaction("recurring", "2026-08-15T09:00:00Z", "-9.99", "Music subscription", "Music", recurrenceRuleId = "rule"),
        transaction("older", "2026-05-01T09:00:00Z", "-42.00", "Old purchase", "Shopping"),
    )

    @Test
    fun `matches iOS text search across note category and amount`() {
        assertEquals(listOf("expense"), search("coffee"))
        assertEquals(listOf("income"), search("salary"))
        assertEquals(listOf("expense"), search("19.99"))
    }

    @Test
    fun `applies signed type category magnitude and recurring filters together`() {
        val result = TransactionSearch.filter(
            transactions = transactions,
            searchText = "",
            filters = TransactionFilters(
                type = TransactionTypeFilter.EXPENSE,
                categories = setOf("Music"),
                amountMin = BigDecimal("9"),
                amountMax = BigDecimal("10"),
                recurringOnly = true,
            ),
            zoneId = zoneId,
            clock = clock,
        )

        assertEquals(listOf("recurring"), result.map { it.id })
    }

    @Test
    fun `custom date range includes the full final day and excludes the following day`() {
        val result = TransactionSearch.filter(
            transactions = listOf(
                transaction("included", "2026-09-02T20:00:00Z", "-5", "", "Coffee"),
                transaction("excluded", "2026-09-03T00:30:00Z", "-5", "", "Coffee"),
            ),
            searchText = "",
            filters = TransactionFilters(
                dateRange = SearchDateRange.Custom(
                    from = LocalDate.of(2026, 9, 2),
                    to = LocalDate.of(2026, 9, 2),
                ),
            ),
            zoneId = zoneId,
            clock = clock,
        )

        assertEquals(listOf("included"), result.map { it.id })
    }

    private fun search(text: String): List<String> = TransactionSearch.filter(
        transactions = transactions,
        searchText = text,
        filters = TransactionFilters(),
        zoneId = zoneId,
        clock = clock,
    ).map { it.id }

    private fun transaction(
        id: String,
        timestamp: String,
        amount: String,
        note: String,
        categoryLabel: String,
        recurrenceRuleId: String? = null,
    ) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse(timestamp),
        amount = BigDecimal(amount),
        note = note,
        categoryLabel = categoryLabel,
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = recurrenceRuleId,
    )
}
