package com.rizzog99.personalfinancetracker.domain.recurrence

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #295: whole-history fixed-expense detection and forecast-only payment matching. The `ac0x`
 * fixtures are the issue's; the rest port iOS `CommittedSpendingDetectionTests` at b649dff, each
 * with its own "today".
 */
class RecurrenceDetectorTest {
    private val utc: ZoneId = ZoneOffset.UTC
    private var nextId = 0

    private fun day(year: Int, month: Int, day: Int): Instant = LocalDate.of(year, month, day).atTime(12, 0).toInstant(ZoneOffset.UTC)

    private fun row(
        note: String,
        amount: String,
        date: Instant,
        ruleId: String? = null,
        goalId: String? = null,
        category: String = "Bills",
    ) = FinanceTransaction(
        id = "t${nextId++}", timestamp = date, amount = BigDecimal(amount), note = note, categoryLabel = category,
        categoryId = null, currencyCode = "EUR", goalId = goalId, recurrenceRuleId = ruleId,
    )

    private fun transfer(goalId: String, amount: String, date: Instant) = row("", amount, date, goalId = goalId, category = "→ Emergency fund")

    private fun rule(
        startDate: Instant,
        amount: String,
        note: String = "",
        lastMaterializedDate: Instant? = null,
        autoRecord: Boolean = true,
        goalId: String? = null,
        endDate: Instant? = null,
    ) = RecurrenceRule(
        id = "r${nextId++}", frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = startDate, endDate = endDate,
        lastMaterializedDate = lastMaterializedDate, amount = BigDecimal(amount), note = note, categoryLabel = "Bills",
        categoryId = null, currencyCode = "EUR", goalId = goalId, autoRecord = autoRecord,
    )

    private fun detect(
        rows: List<FinanceTransaction>,
        today: Instant,
        rules: List<RecurrenceRule> = emptyList(),
        dismissed: List<DismissedRecurrencePattern> = emptyList(),
    ) = RecurrenceDetector.detect(rows, rules, dismissed, today, utc)

    private fun assertAmount(expected: String, actual: BigDecimal) = assertEquals(0, BigDecimal(expected).compareTo(actual))

    // region AC-01 — the issue's fixture, today 2026-11-03

    private val acToday = day(2026, 11, 3)
    private val goal = "goal-G"

    private fun acHistory() = listOf(
        row("Affitto agosto", "-750.00", day(2026, 8, 1)), row("Affitto settembre", "-750.00", day(2026, 9, 1)),
        row("Affitto ottobre", "-750.00", day(2026, 10, 1)),
        // The one row the November import brings: the rest of the series is already history.
        row("Affitto novembre", "-750.00", day(2026, 11, 1)),
        row("Luce", "-62.10", day(2026, 8, 5)), row("Luce", "-66.40", day(2026, 9, 5)), row("Luce", "-58.90", day(2026, 10, 5)),
        transfer(goal, "-200.00", day(2026, 8, 10)), transfer(goal, "-200.00", day(2026, 9, 10)), transfer(goal, "-200.00", day(2026, 10, 10)),
    )

    @Test
    fun `ac01 detects fixed payments, a variable bill and a goal contribution across the whole history`() {
        val results = detect(acHistory(), acToday)

        assertEquals(3, results.size)
        val (rent, saving, bill) = results
        assertEquals("Affitto", RecurrenceDetector.normalizeNote(rent.note).replaceFirstChar(Char::uppercase))
        assertEquals(RecurrenceFrequency.MONTHLY to 1, rent.frequency to rent.interval)
        assertAmount("-750.00", rent.amount)
        assertTrue(rent.isHighConfidence)
        assertTrue(rent.offersAutoRecord)
        assertEquals(4, rent.occurrenceCount)
        assertEquals(day(2026, 12, 1), rent.nextDate)

        assertEquals(goal, saving.goalId)
        assertAmount("-200.00", saving.amount)
        assertTrue(saving.offersAutoRecord)

        assertEquals("Luce", bill.note)
        assertAmount("-62.10", bill.amount) // median
        assertFalse(bill.amountsIdentical)
        assertTrue(bill.isHighConfidence)
        assertFalse(bill.offersAutoRecord)
        assertEquals(day(2026, 11, 5), bill.nextDate)
    }

    @Test
    fun `ac01 a two-payment 6 euro subscription is suggested but does not start checked`() {
        val results = detect(acHistory() + listOf(row("App", "-6", day(2026, 9, 20)), row("App", "-6", day(2026, 10, 20))), acToday)
        val app = results.single { it.note == "App" }
        assertFalse(app.isHighConfidence)
        assertEquals("App", results.last().note)
    }

    @Test
    fun `month names are stripped from notes`() {
        assertEquals("affitto", RecurrenceDetector.normalizeNote("Affitto Ottobre 2026"))
        assertEquals("rent", RecurrenceDetector.normalizeNote("Rent - Sep."))
        assertEquals("netflix com", RecurrenceDetector.normalizeNote("Netflix.com"))
    }

    @Test
    fun `two identical payments are enough`() {
        val results = detect(listOf(row("Affitto settembre", "-700", day(2026, 9, 1)), row("Affitto ottobre", "-700", day(2026, 10, 1))), day(2026, 10, 4))
        assertEquals(1, results.size)
        assertTrue(results[0].amountsIdentical)
        assertEquals(RecurrenceFrequency.MONTHLY, results[0].frequency)
    }

    @Test
    fun `a typed and an imported price compare equal to the cent`() {
        val results = detect(
            listOf(row("Netflix", "-8.99000000000000020", day(2026, 9, 3)), row("Netflix", "-8.99", day(2026, 10, 3))),
            day(2026, 10, 4),
        )
        assertEquals(1, results.size)
        assertTrue(results[0].amountsIdentical)
    }

    @Test
    fun `a variable bill with time-of-day drift is detected`() {
        val rome = ZoneId.of("Europe/Rome")
        val results = RecurrenceDetector.detect(
            listOf(
                row("Electricity bill", "-66", Instant.parse("2026-08-01T12:16:00Z")),
                row("Electricity Bill", "-62.5", Instant.parse("2026-09-01T12:12:00Z")),
                row("Electricity bill", "-65.43", Instant.parse("2026-10-01T11:54:43Z")),
            ),
            emptyList(), emptyList(), Instant.parse("2026-10-04T13:00:00Z"), rome,
        )
        assertEquals(1, results.size)
    }

    // endregion
    // region AC-02 — false positives (iOS #207)

    @Test
    fun `ac02 two yearly gifts are not suggested`() {
        val results = detect(
            listOf(
                row("Regalo Sofia", "-10", day(2025, 12, 9)), row("Regalo Sofia", "-10", day(2026, 12, 9)),
                row("San Martino", "-35", day(2024, 11, 11)), row("San Martino", "-35", day(2025, 11, 11)),
            ),
            day(2025, 11, 20),
        )
        assertEquals(emptyList<RecurrenceSuggestion>(), results)
    }

    @Test
    fun `ac02 yearly needs three payments or an identical bill`() {
        val insurance = listOf(row("Assicurazione", "-420", day(2024, 3, 1)), row("Assicurazione", "-420", day(2025, 3, 2)))
        val results = detect(insurance, day(2025, 3, 10))
        assertEquals(1, results.size)
        assertFalse("shown, but starts unchecked", results[0].isHighConfidence)

        val drifted = listOf(row("Assicurazione", "-420", day(2024, 3, 1)), row("Assicurazione", "-420", day(2025, 3, 31)))
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(drifted, day(2025, 4, 5)))
    }

    @Test
    fun `ac02 a 3,50 weekly coffee and a merchant paid at many prices are not suggested`() {
        val coffee = (0..5).map { row("Caffè", "-3.50", day(2026, 9, 22).plusSeconds(it * 7 * 86_400L)) }
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(coffee, acToday))

        // Groceries: many prices; the two €42 a month apart are a coincidence.
        val groceries = listOf(row("Coop", "-42", day(2026, 9, 12)), row("Coop", "-42", day(2026, 10, 12))) +
            listOf("-12.30", "-88.10", "-25.00", "-61.75", "-7.40", "-130.00").mapIndexed { i, amount -> row("Coop", amount, day(2026, 9, 2 + i * 4)) }
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(groceries, day(2026, 10, 14)))

        // iOS fixtures: small amounts, and the metro's many tickets.
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(listOf(row("Caffè", "-1.20", day(2026, 8, 5)), row("Caffè", "-1.20", day(2026, 9, 5))), day(2026, 9, 10)))
        val metro = listOf(row("Metro Roma", "-4.50", day(2026, 8, 5)), row("Metro Roma", "-4.50", day(2026, 9, 5))) +
            (1..6).map { row("Metro Roma", "-1.50", day(2026, 8, it * 4)) }
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(metro, day(2026, 9, 10)))
    }

    @Test
    fun `ac02 a subscription last paid in May is not suggested`() {
        val gym = listOf(row("Gym", "-40", day(2026, 3, 3)), row("Gym", "-40", day(2026, 4, 3)), row("Gym", "-40", day(2026, 5, 3)))
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(gym, acToday))
        assertEquals(1, detect(gym, day(2026, 5, 20)).size)
    }

    @Test
    fun `ac02 an irregular cadence is not suggested`() {
        val barber = listOf(row("Barber", "-20", day(2026, 6, 1)), row("Barber", "-20", day(2026, 8, 10)))
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(barber, day(2026, 8, 15)))
    }

    @Test
    fun `variable amounts need three payments within tolerance`() {
        val two = listOf(row("Enel", "-80", day(2026, 8, 10)), row("Enel", "-88", day(2026, 9, 10)))
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(two, day(2026, 9, 20)))

        val results = detect(two + row("Enel", "-84", day(2026, 10, 10)), day(2026, 10, 12))
        assertEquals(1, results.size)
        assertFalse(results[0].amountsIdentical)
        assertAmount("-84", results[0].amount)
    }

    @Test
    fun `amounts outside tolerance are different bills`() {
        val results = detect(
            listOf(
                row("Loan", "-100", day(2026, 8, 5)), row("Loan", "-100", day(2026, 9, 5)),
                row("Loan", "-200", day(2026, 8, 5)), row("Loan", "-200", day(2026, 9, 5)),
            ),
            day(2026, 9, 10),
        )
        assertEquals(setOf(-100, -200), results.map { it.amount.toInt() }.toSet())
    }

    @Test
    fun `income, generated rows and empty notes are ignored`() {
        val results = detect(
            listOf(
                row("Salary", "2000", day(2026, 8, 27)), row("Salary", "2000", day(2026, 9, 27)),
                row("Gym", "-40", day(2026, 8, 3), ruleId = "rule"), row("Gym", "-40", day(2026, 9, 3), ruleId = "rule"),
                row("", "-5", day(2026, 8, 1)), row("", "-5", day(2026, 9, 1)),
            ),
            day(2026, 9, 28),
        )
        assertEquals(emptyList<RecurrenceSuggestion>(), results)
    }

    @Test
    fun `strong suggestions come first`() {
        val results = detect(
            listOf(
                row("Affitto", "-700", day(2026, 8, 1)), row("Affitto", "-700", day(2026, 9, 1)),
                row("App", "-6", day(2026, 8, 3)), row("App", "-6", day(2026, 9, 3)),
            ),
            day(2026, 9, 10),
        )
        assertEquals(listOf("Affitto", "App"), results.map { it.note })
        assertTrue(results[0].isHighConfidence)
        assertFalse(results[1].isHighConfidence)
    }

    @Test
    fun `dismissed and existing-rule patterns are skipped`() {
        val rows = listOf(row("Netflix", "-12.99", day(2026, 8, 5)), row("Netflix", "-12.99", day(2026, 9, 5)))
        val today = day(2026, 9, 10)
        val suggestion = detect(rows, today).single()

        assertEquals(emptyList<RecurrenceSuggestion>(), detect(rows, today, dismissed = listOf(RecurrenceDetector.dismissalPattern(suggestion))))
        // A rule with a slightly different amount (price rise within 15 %) still covers it.
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(rows, today, rules = listOf(rule(day(2026, 1, 5), "-13.99", "NETFLIX"))))
    }

    // endregion
    // region AC-03 — planning vs auto-recording

    @Test
    fun `ac03 a drifting series is anchored on its latest payment`() {
        val suggestion = detect(
            listOf(row("Gym membership", "-39.99", day(2026, 8, 26)), row("Gym Membership", "-39.99", day(2026, 9, 25))),
            day(2026, 10, 4),
        ).single()
        assertEquals(day(2026, 10, 25), suggestion.nextDate)
        val newRule = suggestion.toNewRule(autoRecord = false)
        assertEquals(day(2026, 9, 25), newRule.startDate)
        assertEquals(day(2026, 9, 25), newRule.lastMaterializedDate)
    }

    @Test
    fun `ac03 two payments plan a forecast-only rule and never auto-record`() {
        val suggestion = detect(listOf(row("Rent", "-700", day(2026, 8, 1)), row("Rent", "-700", day(2026, 9, 1))), day(2026, 9, 3)).single()
        assertFalse(suggestion.toNewRule(autoRecord = false).autoRecord)
        assertFalse(suggestion.offersAutoRecord)
        assertFalse("asking for auto-record with two payments still plans only", suggestion.toNewRule(autoRecord = true).autoRecord)
    }

    @Test
    fun `ac03 three identical payments offer auto-record and keep the goal`() {
        val other = "goal-other"
        val results = detect(
            listOf(
                transfer(goal, "-200", day(2026, 7, 1)), transfer(goal, "-200", day(2026, 8, 1)), transfer(goal, "-200", day(2026, 9, 1)),
                // Another goal, same amount and day: its own commitment.
                transfer(other, "-200", day(2026, 9, 1)),
            ),
            day(2026, 9, 3),
        )
        val suggestion = results.single()
        assertEquals(goal, suggestion.goalId)
        assertTrue(suggestion.offersAutoRecord)
        assertTrue(suggestion.toNewRule(autoRecord = true).autoRecord)
        assertEquals(goal, suggestion.toNewRule(autoRecord = false).goalId)
    }

    @Test
    fun `existing or dismissed goal rule skips the suggestion`() {
        val rows = listOf(transfer(goal, "-200", day(2026, 8, 1)), transfer(goal, "-200", day(2026, 9, 1)))
        val today = day(2026, 9, 3)
        val suggestion = detect(rows, today).single()
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(rows, today, dismissed = listOf(RecurrenceDetector.dismissalPattern(suggestion))))
        assertEquals(emptyList<RecurrenceSuggestion>(), detect(rows, today, rules = listOf(rule(day(2026, 1, 1), "-200", goalId = goal))))
        // A nameless expense rule of the same amount is a different commitment.
        assertEquals(1, detect(rows, today, rules = listOf(rule(day(2026, 1, 1), "-200"))).size)
    }

    private fun forecastRule(cursor: Instant) = rule(day(2026, 1, 10), "-80", "Enel", lastMaterializedDate = cursor, autoRecord = false)

    @Test
    fun `ac03 a payment within the window advances the cursor and the amount`() {
        val paid = RecurrenceDetector.paidThrough(forecastRule(day(2026, 9, 10)), listOf(row("ENEL ottobre", "-86", day(2026, 10, 13))), day(2026, 10, 14), utc)
        assertEquals(day(2026, 10, 10), paid?.cursor)
        assertAmount("-86", requireNotNull(paid).amount)
    }

    @Test
    fun `ac03 an early payment counts before the due date`() {
        val paid = RecurrenceDetector.paidThrough(forecastRule(day(2026, 9, 10)), listOf(row("Enel", "-80", day(2026, 10, 6))), day(2026, 10, 6), utc)
        assertEquals(day(2026, 10, 10), paid?.cursor)
    }

    @Test
    fun `ac03 a wrong note, amount or date does not match`() {
        val paid = RecurrenceDetector.paidThrough(
            forecastRule(day(2026, 9, 10)),
            listOf(row("Coop", "-80", day(2026, 10, 10)), row("Enel", "-200", day(2026, 10, 10)), row("Enel", "-80", day(2026, 10, 25))),
            day(2026, 10, 26), utc,
        )
        assertNull(paid)
    }

    @Test
    fun `ac03 a goal rule is paid only by a transfer to that goal`() {
        val goalRule = rule(day(2026, 1, 1), "-200", lastMaterializedDate = day(2026, 9, 1), autoRecord = false, goalId = goal)
        val expense = row("", "-200", day(2026, 10, 1))
        assertNull(RecurrenceDetector.paidThrough(goalRule, listOf(expense), day(2026, 10, 2), utc))
        assertEquals(day(2026, 10, 1), RecurrenceDetector.paidThrough(goalRule, listOf(expense, transfer(goal, "-200", day(2026, 10, 2))), day(2026, 10, 2), utc)?.cursor)
    }

    @Test
    fun `match window is a fifth of the cycle clamped to 3 to 14 days`() {
        assertEquals(3L, RecurrenceDetector.matchWindow(RecurrenceFrequency.WEEKLY, 1).toDays())
        assertEquals(6L, RecurrenceDetector.matchWindow(RecurrenceFrequency.MONTHLY, 1).toDays())
        assertEquals(14L, RecurrenceDetector.matchWindow(RecurrenceFrequency.YEARLY, 1).toDays())
    }

    // endregion
}
