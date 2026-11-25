package com.rizzog99.personalfinancetracker.domain.travel

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** A travel as Activity shows it, derived per pass (iOS `TravelSummary`, `ActivityRow.swift`). */
data class TravelSummary(
    val id: String,
    val name: String,
    val symbolName: String,
    /** Signed sum of the members: a refund inside the trip lowers it. */
    val total: BigDecimal,
    val count: Int,
    /** The newest member, or the creation time of an empty travel. */
    val anchor: Instant,
    val start: Instant?,
    val end: Instant?,
)

/** One Activity row: a plain transaction or a collapsed travel. */
sealed interface ActivityRow {
    val anchor: Instant

    data class Transaction(val transaction: FinanceTransaction) : ActivityRow {
        override val anchor: Instant get() = transaction.timestamp
    }

    data class Travel(val summary: TravelSummary) : ActivityRow {
        override val anchor: Instant get() = summary.anchor
    }
}

data class ActivityDay(val date: LocalDate, val rows: List<ActivityRow>)

/**
 * iOS `ActivityRowGrouper.group`: day sections, newest first, each travel's members collapsed into
 * one row anchored to its newest member. Passing no travels yields plain rows only — how callers
 * opt out while searching, filtering or selecting. A tag whose travel is gone stays a plain row.
 * Empty travels are left out unless [includeEmpty] (the Travels page lists them).
 */
fun groupActivityRows(
    transactions: List<FinanceTransaction>,
    travels: List<FinanceTravel>,
    zone: ZoneId,
    includeEmpty: Boolean = false,
): List<ActivityDay> {
    val byId = travels.associateBy { it.id }
    val members = mutableMapOf<String, MutableList<FinanceTransaction>>()
    val rows = mutableListOf<ActivityRow>()
    transactions.forEach { transaction ->
        val travelId = transaction.travelId
        if (travelId != null && travelId in byId) {
            members.getOrPut(travelId) { mutableListOf() } += transaction
        } else {
            rows += ActivityRow.Transaction(transaction)
        }
    }
    travels.forEach { travel ->
        val group = members[travel.id].orEmpty()
        if (group.isEmpty() && !includeEmpty) return@forEach
        val times = group.map { it.timestamp }
        rows += ActivityRow.Travel(
            TravelSummary(
                id = travel.id,
                name = travel.name,
                symbolName = travel.symbolName,
                total = group.fold(BigDecimal.ZERO) { sum, t -> sum + t.amount },
                count = group.size,
                anchor = times.maxOrNull() ?: travel.createdAt,
                start = times.minOrNull(),
                end = times.maxOrNull(),
            ),
        )
    }
    return rows
        .groupBy { it.anchor.atZone(zone).toLocalDate() }
        .toSortedMap(compareByDescending { it })
        .map { (date, dayRows) -> ActivityDay(date, dayRows.sortedByDescending { it.anchor }) }
}

/** Every travel with its summary, newest anchor first: the Travels page's list. */
fun travelSummaries(transactions: List<FinanceTransaction>, travels: List<FinanceTravel>, zone: ZoneId): List<TravelSummary> =
    groupActivityRows(transactions.filter { it.travelId != null }, travels, zone, includeEmpty = true)
        .flatMap { it.rows }
        .filterIsInstance<ActivityRow.Travel>()
        .map { it.summary }
        .sortedByDescending { it.anchor }
