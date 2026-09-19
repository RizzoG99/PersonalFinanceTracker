package com.rizzog99.personalfinancetracker.domain.transaction

import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
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
    fun `AC-01 typed filters use strict signs and exclude zero`() {
        val signTransactions = listOf(
            transaction("expense", "2026-09-01T09:00:00Z", "-0.01", "", "Other"),
            transaction("zero", "2026-09-01T10:00:00Z", "0", "", "Other"),
            transaction("income", "2026-09-01T11:00:00Z", "0.01", "", "Other"),
        )

        assertEquals(
            listOf("income"),
            filterIds(signTransactions, TransactionFilters(type = TransactionTypeFilter.INCOME)),
        )
        assertEquals(
            listOf("expense"),
            filterIds(signTransactions, TransactionFilters(type = TransactionTypeFilter.EXPENSE)),
        )
        assertEquals(
            listOf("expense", "zero", "income"),
            filterIds(signTransactions, TransactionFilters()),
        )
    }

    @Test
    fun `AC-06 recurring-only composes with signed category and magnitude filters`() {
        val result = TransactionSearch.filter(
            transactions = transactions,
            searchText = "",
            filters = TransactionFilters(
                type = TransactionTypeFilter.EXPENSE,
                category = "Music",
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
    fun `AC-02 same category label remains scoped to the selected transaction type`() {
        val sameLabelTransactions = listOf(
            transaction("income-gift", "2026-09-01T09:00:00Z", "100", "", "Gift"),
            transaction("expense-gift", "2026-09-01T10:00:00Z", "-25", "", "Gift"),
        )

        fun idsFor(type: TransactionTypeFilter) = TransactionSearch.filter(
            transactions = sameLabelTransactions,
            searchText = "",
            filters = TransactionFilters(type = type, category = "Gift"),
            zoneId = zoneId,
            clock = clock,
        ).map(FinanceTransaction::id)

        assertEquals(listOf("income-gift"), idsFor(TransactionTypeFilter.INCOME))
        assertEquals(listOf("expense-gift"), idsFor(TransactionTypeFilter.EXPENSE))
    }

    @Test
    fun `AC-03 preset ranges use inclusive starts and an exclusive fixed now`() {
        fun boundaryTransactions(beforeStart: String, atStart: String) = listOf(
            transaction("before-start", beforeStart, "-1", "", "Other"),
            transaction("at-start", atStart, "-1", "", "Other"),
            transaction("before-now", "2026-09-04T09:59:59Z", "-1", "", "Other"),
            transaction("at-now", "2026-09-04T10:00:00Z", "-1", "", "Other"),
        )

        assertEquals(
            listOf("at-start", "before-now"),
            filterIds(
                boundaryTransactions("2026-08-31T21:59:59Z", "2026-08-31T22:00:00Z"),
                TransactionFilters(dateRange = SearchDateRange.ThisMonth),
            ),
        )
        assertEquals(
            listOf("at-start", "before-now"),
            filterIds(
                boundaryTransactions("2026-06-04T09:59:59Z", "2026-06-04T10:00:00Z"),
                TransactionFilters(dateRange = SearchDateRange.Last3Months),
            ),
        )
        assertEquals(
            listOf("at-start", "before-now"),
            filterIds(
                boundaryTransactions("2025-12-31T22:59:59Z", "2025-12-31T23:00:00Z"),
                TransactionFilters(dateRange = SearchDateRange.ThisYear),
            ),
        )
    }

    @Test
    fun `AC-04 custom date includes the final local day across both DST transitions`() {
        val springForward = listOf(
            transaction("spring-start", "2026-03-28T23:00:00Z", "-1", "", "Other"),
            transaction("spring-last", "2026-03-29T21:59:59Z", "-1", "", "Other"),
            transaction("spring-next-day", "2026-03-29T22:00:00Z", "-1", "", "Other"),
        )
        val fallBack = listOf(
            transaction("fall-start", "2026-10-24T22:00:00Z", "-1", "", "Other"),
            transaction("fall-last", "2026-10-25T22:59:59Z", "-1", "", "Other"),
            transaction("fall-next-day", "2026-10-25T23:00:00Z", "-1", "", "Other"),
        )

        assertEquals(
            listOf("spring-start", "spring-last"),
            filterIds(
                springForward,
                TransactionFilters(
                    dateRange = SearchDateRange.Custom(
                        from = LocalDate.of(2026, 3, 29),
                        to = LocalDate.of(2026, 3, 29),
                    ),
                ),
            ),
        )
        assertEquals(
            listOf("fall-start", "fall-last"),
            filterIds(
                fallBack,
                TransactionFilters(
                    dateRange = SearchDateRange.Custom(
                        from = LocalDate.of(2026, 10, 25),
                        to = LocalDate.of(2026, 10, 25),
                    ),
                ),
            ),
        )
    }

    @Test
    fun `AC-05 amount bounds compare absolute magnitudes inclusively and reject invalid ranges`() {
        val amountTransactions = listOf(
            transaction("below", "2026-09-01T09:00:00Z", "-9.99", "", "Other"),
            transaction("minimum", "2026-09-01T10:00:00Z", "-10", "", "Other"),
            transaction("inside-positive", "2026-09-01T11:00:00Z", "20", "", "Other"),
            transaction("maximum", "2026-09-01T12:00:00Z", "30", "", "Other"),
            transaction("above", "2026-09-01T13:00:00Z", "-30.01", "", "Other"),
        )

        assertEquals(
            listOf("minimum", "inside-positive", "maximum"),
            filterIds(
                amountTransactions,
                TransactionFilters(amountMin = BigDecimal("10"), amountMax = BigDecimal("30")),
            ),
        )
        assertThrows(IllegalArgumentException::class.java) {
            TransactionFilters(amountMin = BigDecimal("30"), amountMax = BigDecimal("10"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            TransactionFilters(amountMin = BigDecimal("-0.01"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            TransactionFilters(amountMax = BigDecimal("-0.01"))
        }
    }

    @Test
    fun `AC-07 text search and every structured constraint compose with logical AND`() {
        val matching = transaction(
            "matching",
            "2026-09-02T09:00:00Z",
            "-10",
            "Coffee subscription",
            "Coffee",
            recurrenceRuleId = "rule",
        )
        val nearMisses = listOf(
            matching.copy(id = "wrong-search", note = "Tea purchase"),
            matching.copy(id = "wrong-type", amount = BigDecimal("10")),
            matching.copy(id = "wrong-category", categoryLabel = "Music"),
            matching.copy(id = "wrong-date", timestamp = Instant.parse("2026-08-01T09:00:00Z")),
            matching.copy(id = "wrong-amount", amount = BigDecimal("-11")),
            matching.copy(id = "not-recurring", recurrenceRuleId = null),
        )

        val result = TransactionSearch.filter(
            transactions = listOf(matching) + nearMisses,
            searchText = "subscription",
            filters = TransactionFilters(
                type = TransactionTypeFilter.EXPENSE,
                category = "Coffee",
                dateRange = SearchDateRange.ThisMonth,
                amountMin = BigDecimal("10"),
                amountMax = BigDecimal("10"),
                recurringOnly = true,
            ),
            zoneId = zoneId,
            clock = clock,
        )

        assertEquals(listOf("matching"), result.map(FinanceTransaction::id))
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

    private fun filterIds(
        source: List<FinanceTransaction>,
        filters: TransactionFilters,
    ): List<String> = TransactionSearch.filter(
        transactions = source,
        searchText = "",
        filters = filters,
        zoneId = zoneId,
        clock = clock,
    ).map(FinanceTransaction::id)

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
