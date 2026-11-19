package com.rizzog99.personalfinancetracker.domain.recurrence

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * A fixed expense found in the history (#295), waiting for "Plan for it" or "Not fixed".
 * Port of iOS `RecurrenceSuggestion` at b649dff (`Utilities/RecurrenceDetector.swift:7-59`).
 */
data class RecurrenceSuggestion(
    val frequency: RecurrenceFrequency,
    val interval: Int,
    /** Median of the group: the forecast for a variable bill. */
    val amount: BigDecimal,
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val currencyCode: String,
    val occurrenceCount: Int,
    /** One cycle after the latest payment, which anchors the rule. */
    val nextDate: Instant,
    /** Sorted; the last anchors the rule and is its cursor. */
    val occurrenceDates: List<Instant>,
    /** Auto-record is only offered when every payment was the same amount. */
    val amountsIdentical: Boolean,
    /** Set for a goal transfer: the rule keeps moving money into that goal. */
    val goalId: String?,
) {
    /** Strong enough evidence to start checked; weaker ones are shown unchecked. */
    val isHighConfidence: Boolean
        get() {
            val size = amount.abs()
            return when (frequency) {
                RecurrenceFrequency.WEEKLY, RecurrenceFrequency.MONTHLY ->
                    occurrenceCount >= 3 || (amountsIdentical && size >= BigDecimal(15))
                RecurrenceFrequency.YEARLY -> occurrenceCount >= 3 && size >= BigDecimal(20)
            }
        }

    /** Recording transactions for the user needs more than two matching payments. */
    val offersAutoRecord: Boolean get() = amountsIdentical && occurrenceCount >= 3

    /**
     * A forecast-only rule (or auto-record, only when [offersAutoRecord]) anchored on the latest
     * payment, which is also its cursor: that payment is covered, the next is one cycle later.
     * [categoryId]/[categoryLabel] override the detected ones, for a category an import just created.
     */
    fun toNewRule(
        autoRecord: Boolean,
        categoryLabel: String = this.categoryLabel,
        categoryId: String? = this.categoryId,
    ) = NewRecurrenceRule(
        frequency = frequency,
        interval = interval,
        startDate = occurrenceDates.last(),
        amount = amount,
        note = note,
        categoryLabel = categoryLabel,
        categoryId = categoryId,
        currencyCode = currencyCode,
        goalId = goalId,
        autoRecord = autoRecord && offersAutoRecord,
        lastMaterializedDate = occurrenceDates.last(),
    )
}

/** A "Not fixed" answer, matched like an existing rule: same goal or normalised note, amount within tolerance. */
data class DismissedRecurrencePattern(val note: String, val amount: BigDecimal, val goalId: String? = null)

/**
 * Committed-spending detection: finds fixed expenses in the whole history and tells whether a
 * forecast-only rule's payments have arrived. 1:1 port of iOS `RecurrenceDetector` at b649dff;
 * the line references below point there.
 */
object RecurrenceDetector {
    /** Amounts within this fraction of each other count as the same bill. */
    private val amountTolerance = BigDecimal("0.15")
    /** Below this a repeat is a ticket or a coffee, not a bill. */
    private val minimumAmount = BigDecimal(5)

    fun detect(
        transactions: List<FinanceTransaction>,
        existingRules: List<RecurrenceRule>,
        dismissed: List<DismissedRecurrencePattern> = emptyList(),
        today: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<RecurrenceSuggestion> {
        // Expenses the user (or a bank file) recorded; generated rows already belong to a rule.
        val candidates = transactions.filter { it.amount.signum() < 0 && it.recurrenceRuleId == null }
        val byKey = candidates.groupBy { commitmentKey(it.goalId, it.note) }

        val suggestions = mutableListOf<RecurrenceSuggestion>()
        for ((key, rows) in byKey) {
            if (key.goalId == null && key.note.isEmpty()) continue
            for (group in amountClusters(rows)) {
                // To the cent: a typed amount and the same price parsed from a file must compare equal.
                val identical = group.map { it.amount.setScale(2, RoundingMode.HALF_UP) }.toSet().size == 1
                if (group.size < (if (identical) 2 else 3)) continue
                val amount = median(group.map { it.amount })
                val size = amount.abs()
                if (size < minimumAmount) continue
                // Everyday spending: a merchant paid at many prices can have one bucket that looks periodic.
                if (group.size * 2 < rows.size) continue

                val dates = group.map { it.timestamp }.sorted()
                val cadence = inferFrequency(dates, zoneId)?.takeIf(::isSupported) ?: continue
                // Two payments a year apart is the weakest evidence there is (birthday gifts pass it).
                if (cadence.first == RecurrenceFrequency.YEARLY) {
                    if (!(group.size >= 3 || (identical && size >= BigDecimal(50)))) continue
                    val gapsOk = dates.zipWithNext { a, b -> Duration.between(a, b).toMillis() / 86_400_000.0 }
                        .all { abs(it - 365.25) <= 14 }
                    if (!gapsOk) continue
                }

                // Recency gate: the next payment's window must still be open, or a subscription
                // cancelled last year would be suggested.
                val lastDate = dates.last()
                val nextDate = RecurrenceOccurrenceCalculator.occurrences(
                    frequency = cadence.first,
                    interval = cadence.second,
                    startDate = lastDate,
                    endDate = null,
                    since = lastDate,
                    through = lastDate.plus(Duration.ofDays(400)),
                    zoneId = zoneId,
                ).firstOrNull() ?: continue
                if (nextDate.plus(matchWindow(cadence.first, cadence.second)) < today) continue

                if (existingRules.any { commitmentKey(it.goalId, it.note) == key && isSameAmount(it.amount, amount) }) continue

                val suggestion = RecurrenceSuggestion(
                    frequency = cadence.first,
                    interval = cadence.second,
                    amount = amount,
                    note = mostCommon(group.map { it.note }) ?: group[0].note,
                    categoryLabel = mostCommon(group.map { it.categoryLabel }) ?: group[0].categoryLabel,
                    categoryId = group.firstNotNullOfOrNull { it.categoryId },
                    currencyCode = group[0].currencyCode,
                    occurrenceCount = group.size,
                    nextDate = nextDate,
                    occurrenceDates = dates,
                    amountsIdentical = identical,
                    goalId = key.goalId,
                )
                if (!isDismissed(suggestion, dismissed)) suggestions += suggestion
            }
        }

        // Likeliest and biggest first: rent before a €6 subscription before a maybe.
        return suggestions.sortedWith(
            compareByDescending<RecurrenceSuggestion> { it.isHighConfidence }
                .thenByDescending { it.amount.abs() }
                .thenByDescending { it.occurrenceCount }
                .thenBy { it.note },
        )
    }

    fun dismissalPattern(suggestion: RecurrenceSuggestion) =
        DismissedRecurrencePattern(normalizeNote(suggestion.note), suggestion.amount, suggestion.goalId)

    fun isDismissed(suggestion: RecurrenceSuggestion, patterns: List<DismissedRecurrencePattern>): Boolean {
        val key = commitmentKey(suggestion.goalId, suggestion.note)
        return patterns.any { commitmentKey(it.goalId, it.note) == key && isSameAmount(it.amount, suggestion.amount) }
    }

    /**
     * How far from its due date a payment still counts: ±20 % of the cycle, 3–14 days
     * (monthly ≈ ±6 days). Below half a cycle, so windows never overlap.
     */
    fun matchWindow(frequency: RecurrenceFrequency, interval: Int): Duration {
        val cycle = when (frequency) {
            RecurrenceFrequency.WEEKLY -> 7.0
            RecurrenceFrequency.MONTHLY -> 30.4
            RecurrenceFrequency.YEARLY -> 365.25
        }
        // Swift's .rounded() is half away from zero; roundToInt is half up — same for these positives.
        return Duration.ofDays((cycle * interval * 0.2).roundToInt().coerceIn(3, 14).toLong())
    }

    /** The cursor and amount a forecast-only rule's matched payments have paid through. */
    data class Paid(val cursor: Instant, val amount: BigDecimal)

    /**
     * The last occurrence of a forecast-only rule that a real expense has paid (same goal or note,
     * amount within tolerance, date within the window, early payments included). Null when nothing
     * new matched.
     */
    fun paidThrough(
        rule: RecurrenceRule,
        transactions: List<FinanceTransaction>,
        today: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): Paid? {
        val window = matchWindow(rule.frequency, rule.interval)
        val key = commitmentKey(rule.goalId, rule.note)
        val payments = transactions.filter {
            it.amount.signum() < 0 && it.recurrenceRuleId == null &&
                isSameAmount(it.amount, rule.amount) && commitmentKey(it.goalId, it.note) == key
        }.toMutableList()
        val occurrences = RecurrenceOccurrenceCalculator.occurrences(
            frequency = rule.frequency,
            interval = rule.interval,
            startDate = rule.startDate,
            endDate = rule.endDate,
            since = rule.lastMaterializedDate,
            through = today.plus(window),
            zoneId = zoneId,
        )
        var paid: Paid? = null
        for (occurrence in occurrences) {
            val match = payments
                .filter { Duration.between(occurrence, it.timestamp).abs() <= window }
                .minByOrNull { Duration.between(occurrence, it.timestamp).abs() }
                ?: continue
            payments.remove(match)
            paid = Paid(occurrence, match.amount)
        }
        return paid
    }

    data class CommitmentKey(val goalId: String?, val note: String)

    /** A goal transfer is its goal (usually nameless), anything else its normalised note. */
    fun commitmentKey(goalId: String?, note: String) = CommitmentKey(goalId, if (goalId == null) normalizeNote(note) else "")

    /** Lowercase, letters only, month names dropped ("Affitto Ottobre 2026" → "affitto"). */
    fun normalizeNote(note: String): String =
        note.lowercase().map { if (it.isLetter()) it else ' ' }.joinToString("")
            .split(' ').filter { it.isNotEmpty() && it !in monthNames }.joinToString(" ")

    // ponytail: hardcoded EN/IT full + short names (iOS derives them from DateFormatter); JVM CLDR
    // and device ICU disagree on short forms, so a fixed list keeps tests and devices identical.
    private val monthNames = setOf(
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
        "gen", "mag", "giu", "lug", "ago", "set", "ott", "dic",
    )

    fun isSameAmount(a: BigDecimal, b: BigDecimal): Boolean = (a - b).abs() <= b.abs() * amountTolerance

    /** Sorted by size, a new cluster starts whenever an amount is out of tolerance of the cluster's smallest. */
    private fun amountClusters(rows: List<FinanceTransaction>): List<List<FinanceTransaction>> {
        val clusters = mutableListOf<MutableList<FinanceTransaction>>()
        for (row in rows.sortedBy { it.amount.abs() }) {
            val base = clusters.lastOrNull()?.first()
            if (base != null && isSameAmount(row.amount, base.amount)) clusters.last() += row else clusters += mutableListOf(row)
        }
        return clusters
    }

    private fun median(amounts: List<BigDecimal>): BigDecimal = amounts.sorted().let { it[it.size / 2] }

    /** Only the cadences fixed expenses actually have. */
    private fun isSupported(cadence: Pair<RecurrenceFrequency, Int>) = when (cadence.first) {
        RecurrenceFrequency.WEEKLY -> cadence.second <= 2
        RecurrenceFrequency.MONTHLY -> cadence.second <= 3
        RecurrenceFrequency.YEARLY -> cadence.second == 1
    }

    private fun inferFrequency(dates: List<Instant>, zoneId: ZoneId): Pair<RecurrenceFrequency, Int>? {
        val gaps = dates.zipWithNext { a, b -> ChronoUnit.DAYS.between(a.atZone(zoneId), b.atZone(zoneId)) }.filter { it > 0 }
        if (gaps.isEmpty()) return null
        val medianGap = gaps.sorted()[gaps.size / 2].toDouble()
        val tolerance = medianGap * 0.2
        if (gaps.any { it < medianGap - tolerance || it > medianGap + tolerance }) return null
        if (medianGap in 28.0..31.0) return RecurrenceFrequency.MONTHLY to 1

        // Coarsest first: "every 3 months" rather than "every 13 weeks" for the same gap.
        for ((frequency, days, maxInterval) in listOf(
            Triple(RecurrenceFrequency.YEARLY, 365.25, 10),
            Triple(RecurrenceFrequency.MONTHLY, 30.4, 24),
            Triple(RecurrenceFrequency.WEEKLY, 7.0, 52),
        )) {
            val interval = (medianGap / days).roundToInt()
            if (interval in 1..maxInterval && abs(medianGap - days * interval) / (days * interval) <= 0.10) {
                return frequency to interval
            }
        }
        return null
    }

    private fun mostCommon(values: List<String>): String? =
        values.groupingBy { it }.eachCount().entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .firstOrNull()?.key
}
