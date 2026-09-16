package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** A group of imported rows that look like the same repeating transaction. */
data class RecurringCandidate(
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val amount: BigDecimal,
    val currencyCode: String,
    val frequency: RecurrenceFrequency,
    val interval: Int,
    val occurrences: Int,
    val nextDate: Instant,
)

/**
 * Groups just-imported rows by (note, category, amount) and flags groups of 2+ whose gaps
 * between occurrences land in a recognisable weekly/monthly/yearly band, proposing the next
 * occurrence date one interval after the last one actually seen.
 *
 * ponytail: fixed day-gap bands rather than a real periodicity fit — good enough for a bank
 * statement's regular subscriptions/rent, misses biweekly-ish or irregular gaps. Upgrade to a
 * proper interval-variance check if that turns out to matter.
 */
object RecurringImportDetector {
    private val zoneId: ZoneId = ZoneId.systemDefault()

    fun detect(transactions: List<FinanceTransaction>): List<RecurringCandidate> = transactions
        .groupBy { Triple(it.note.normalized(), it.categoryLabel, it.amount) }
        .mapNotNull { (key, group) -> group.takeIf { it.size >= 2 }?.let { candidate(key.second, it) } }
        .sortedByDescending(RecurringCandidate::occurrences)

    private fun candidate(categoryLabel: String, group: List<FinanceTransaction>): RecurringCandidate? {
        val sorted = group.sortedBy { it.timestamp }
        val gaps = sorted.zipWithNext { a, b -> ChronoUnit.DAYS.between(a.timestamp.atZone(zoneId), b.timestamp.atZone(zoneId)) }
        val medianGap = gaps.sorted().let { it[it.size / 2] }
        val (frequency, interval) = cadenceFor(medianGap) ?: return null
        val last = sorted.last()
        return RecurringCandidate(
            note = last.note,
            categoryLabel = categoryLabel,
            categoryId = last.categoryId,
            amount = last.amount,
            currencyCode = last.currencyCode,
            frequency = frequency,
            interval = interval,
            occurrences = sorted.size,
            nextDate = last.timestamp.plusOneInterval(frequency, interval),
        )
    }

    private fun cadenceFor(medianGapDays: Long): Pair<RecurrenceFrequency, Int>? = when (medianGapDays) {
        in 5..10 -> RecurrenceFrequency.WEEKLY to 1
        in 12..17 -> RecurrenceFrequency.WEEKLY to 2
        in 25..35 -> RecurrenceFrequency.MONTHLY to 1
        in 58..66 -> RecurrenceFrequency.MONTHLY to 2
        in 350..380 -> RecurrenceFrequency.YEARLY to 1
        else -> null
    }

    private fun Instant.plusOneInterval(frequency: RecurrenceFrequency, interval: Int): Instant {
        val date = atZone(zoneId)
        return when (frequency) {
            RecurrenceFrequency.WEEKLY -> date.plusWeeks(interval.toLong())
            RecurrenceFrequency.MONTHLY -> date.plusMonths(interval.toLong())
            RecurrenceFrequency.YEARLY -> date.plusYears(interval.toLong())
        }.toInstant()
    }

    /** Bank exports pad the same merchant with a reference number each time — strip digits so
     * "NETFLIX 4471" and "NETFLIX 8823" still group together. */
    private fun String.normalized(): String = lowercase().replace(Regex("[0-9]+"), "").replace(Regex("\\s+"), " ").trim()
}
