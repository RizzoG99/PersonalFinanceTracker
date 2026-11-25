package com.rizzog99.personalfinancetracker.domain.travel

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #284 AC-01 / AC-02 arithmetic, against frozen iOS `ActivityRow.swift` (grouper) and
 * `TravelReport.swift`. Fixture T from the issue: Barcellona = Hotel, Taxi, Rimborso; Caffè untagged;
 * Montagna empty.
 */
class TravelDomainTest {
    private val zone = ZoneId.of("Europe/Rome")
    private val barcellona = FinanceTravel("trip-b", "Barcellona", "airplane", Instant.parse("2026-09-01T08:00:00Z"))
    private val montagna = FinanceTravel("trip-m", "Montagna", "mountain.2", Instant.parse("2026-09-20T08:00:00Z"))

    private fun row(id: String, date: String, amount: String, category: String, travel: String? = null) = FinanceTransaction(
        id = id, timestamp = Instant.parse("${date}T10:00:00Z"), amount = BigDecimal(amount), note = id,
        categoryLabel = category, categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null, travelId = travel,
    )

    private val hotel = row("Hotel", "2026-09-12", "-250.00", "Travel", "trip-b")
    private val taxi = row("Taxi", "2026-09-14", "-30.00", "Taxi & Rideshare", "trip-b")
    private val refund = row("Rimborso", "2026-09-16", "50.00", "Refund", "trip-b")
    private val coffee = row("Caffè", "2026-09-15", "-3.00", "Coffee & Drinks")
    private val ledger = listOf(refund, coffee, taxi, hotel)

    @Test
    fun ac01_aTripCollapsesIntoOneRowOnItsNewestDay() {
        val days = groupActivityRows(ledger, listOf(barcellona, montagna), zone)

        assertEquals(listOf(LocalDate.parse("2026-09-16"), LocalDate.parse("2026-09-15")), days.map { it.date })
        val trip = (days[0].rows.single() as ActivityRow.Travel).summary
        assertEquals("Barcellona", trip.name)
        assertEquals(0, BigDecimal("-230.00").compareTo(trip.total))
        assertEquals(3, trip.count)
        assertEquals(hotel.timestamp, trip.start)
        assertEquals(refund.timestamp, trip.end)
        assertEquals(listOf(ActivityRow.Transaction(coffee)), days[1].rows)
        // Montagna is empty: not an event, so not in Activity.
        assertTrue(days.flatMap { it.rows }.none { it is ActivityRow.Travel && it.summary.id == "trip-m" })
    }

    @Test
    fun ac01_noTravelsMeansPlainRowsAndAnOrphanTagStaysPlain() {
        assertEquals(4, groupActivityRows(ledger, emptyList(), zone).sumOf { it.rows.size })
        val orphan = row("Orphan", "2026-09-10", "-1.00", "Other", "gone")
        val days = groupActivityRows(listOf(orphan), listOf(barcellona), zone)
        assertEquals(listOf(ActivityRow.Transaction(orphan)), days.single().rows)
    }

    @Test
    fun ac03_theTravelsListKeepsEmptyTravels() {
        val summaries = travelSummaries(ledger, listOf(barcellona, montagna), zone)
        assertEquals(listOf("Montagna", "Barcellona"), summaries.map { it.name })
        assertEquals(0, summaries.first().count)
        assertEquals(montagna.createdAt, summaries.first().anchor)
    }

    @Test
    fun ac02_theReportMatchesIos() {
        val report = TravelReport.of(listOf(hotel, taxi, refund), zone)
        assertEquals(0, BigDecimal("280.00").compareTo(report.spent))
        assertEquals(0, BigDecimal("50.00").compareTo(report.refunded))
        assertEquals(0, BigDecimal("-230.00").compareTo(report.net))
        assertEquals(5, report.dayCount)
        assertEquals(BigDecimal("56.00"), report.perDay)
        assertEquals(listOf("Travel", "Taxi & Rideshare"), report.categories.map { it.first })
        assertEquals(LocalDate.parse("2026-09-12"), report.start)
        assertEquals(LocalDate.parse("2026-09-16"), report.end)
    }

    @Test
    fun ac02_emptyAndOneDayTrips() {
        val empty = TravelReport.of(emptyList(), zone)
        assertEquals(0, empty.dayCount)
        assertEquals(0, BigDecimal.ZERO.compareTo(empty.perDay))
        val oneDay = TravelReport.of(listOf(hotel), zone)
        assertEquals(1, oneDay.dayCount)
        assertEquals(BigDecimal("250.00"), oneDay.perDay)
    }

    @Test
    fun ac02_categoryTiesBreakByName() {
        val a = row("a", "2026-09-12", "-10.00", "Zeta", "trip-b")
        val b = row("b", "2026-09-12", "-10.00", "Alpha", "trip-b")
        assertEquals(listOf("Alpha", "Zeta"), TravelReport.of(listOf(a, b), zone).categories.map { it.first })
    }
}
