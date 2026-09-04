package com.rizzog99.personalfinancetracker.domain.transaction

import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

enum class TransactionTypeFilter {
    ALL,
    INCOME,
    EXPENSE,
}

sealed interface SearchDateRange {
    data object ThisMonth : SearchDateRange
    data object Last3Months : SearchDateRange
    data object ThisYear : SearchDateRange
    data class Custom(val from: LocalDate, val to: LocalDate) : SearchDateRange
}

data class TransactionFilters(
    val type: TransactionTypeFilter = TransactionTypeFilter.ALL,
    val categories: Set<String> = emptySet(),
    val dateRange: SearchDateRange? = null,
    val amountMin: BigDecimal? = null,
    val amountMax: BigDecimal? = null,
    val recurringOnly: Boolean = false,
) {
    init {
        require(amountMin == null || amountMin >= BigDecimal.ZERO) { "Minimum amount cannot be negative." }
        require(amountMax == null || amountMax >= BigDecimal.ZERO) { "Maximum amount cannot be negative." }
        require(amountMin == null || amountMax == null || amountMin <= amountMax) {
            "Minimum amount cannot exceed maximum amount."
        }
    }

    val isActive: Boolean
        get() = type != TransactionTypeFilter.ALL || categories.isNotEmpty() || dateRange != null ||
            amountMin != null || amountMax != null || recurringOnly
}

object TransactionSearch {
    fun filter(
        transactions: List<FinanceTransaction>,
        searchText: String,
        filters: TransactionFilters,
        zoneId: ZoneId,
        clock: Clock = Clock.system(zoneId),
    ): List<FinanceTransaction> {
        val dateBounds = filters.dateRange?.bounds(zoneId, clock)
        return transactions.filter { transaction ->
            transaction.matchesSearch(searchText) && transaction.matchesFilters(filters, dateBounds)
        }
    }
}

private fun FinanceTransaction.matchesSearch(searchText: String): Boolean {
    if (searchText.isBlank()) return true
    return note.contains(searchText, ignoreCase = true) ||
        categoryLabel.contains(searchText, ignoreCase = true) ||
        MoneyCodec.encode(amount).contains(searchText, ignoreCase = true)
}

private fun FinanceTransaction.matchesFilters(
    filters: TransactionFilters,
    dateBounds: ClosedOpenInstantRange?,
): Boolean {
    when (filters.type) {
        TransactionTypeFilter.ALL -> Unit
        TransactionTypeFilter.INCOME -> if (amount <= BigDecimal.ZERO) return false
        TransactionTypeFilter.EXPENSE -> if (amount >= BigDecimal.ZERO) return false
    }
    if (filters.categories.isNotEmpty() && categoryLabel !in filters.categories) return false
    if (dateBounds != null && timestamp !in dateBounds) return false
    if (filters.amountMin != null && amount.abs() < filters.amountMin) return false
    if (filters.amountMax != null && amount.abs() > filters.amountMax) return false
    if (filters.recurringOnly && recurrenceRuleId == null) return false
    return true
}

private data class ClosedOpenInstantRange(val start: Instant, val endExclusive: Instant) {
    operator fun contains(value: Instant): Boolean = !value.isBefore(start) && value.isBefore(endExclusive)
}

private fun SearchDateRange.bounds(zoneId: ZoneId, clock: Clock): ClosedOpenInstantRange {
    val today = LocalDate.now(clock.withZone(zoneId))
    val now = clock.instant()
    return when (this) {
        SearchDateRange.ThisMonth -> ClosedOpenInstantRange(
            start = today.withDayOfMonth(1).atStartOfDay(zoneId).toInstant(),
            endExclusive = now,
        )
        SearchDateRange.Last3Months -> ClosedOpenInstantRange(
            start = now.atZone(zoneId).minusMonths(3).toInstant(),
            endExclusive = now,
        )
        SearchDateRange.ThisYear -> ClosedOpenInstantRange(
            start = today.withDayOfYear(1).atStartOfDay(zoneId).toInstant(),
            endExclusive = now,
        )
        is SearchDateRange.Custom -> {
            require(!to.isBefore(from)) { "Custom date range ends before it starts." }
            ClosedOpenInstantRange(
                start = from.atStartOfDay(zoneId).toInstant(),
                endExclusive = to.plusDays(1).atStartOfDay(zoneId).toInstant(),
            )
        }
    }
}
