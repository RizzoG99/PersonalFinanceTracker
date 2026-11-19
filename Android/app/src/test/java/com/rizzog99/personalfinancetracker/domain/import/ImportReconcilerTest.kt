package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

/** #314: each matching rule of [ImportReconciler] against its own generated payment. */
class ImportReconcilerTest {
    private val paidAt: Instant = Instant.parse("2026-03-01T12:00:00Z")

    private fun tx(amount: String, at: Instant, note: String = "NETFLIX.COM", ruleId: String? = null) = FinanceTransaction(
        id = "$note-$amount-$at", timestamp = at, amount = BigDecimal(amount), note = note, categoryLabel = "Bills",
        categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = ruleId,
    )

    private val generated = tx("-9.99", paidAt, note = "Netflix", ruleId = "rule-1")

    /** True when [row] is treated as the bank's copy of [generated]. */
    private fun matches(row: FinanceTransaction, existing: List<FinanceTransaction> = listOf(generated)) =
        ImportReconciler.split(listOf(row), existing).second.isNotEmpty()

    @Test fun `same amount at another scale matches`() = assertEquals(true, matches(tx("-9.990", paidAt)))

    @Test fun `amount equal to the cent after rounding matches`() = assertEquals(true, matches(tx("-9.994", paidAt)))

    @Test fun `amount a cent off does not match`() = assertEquals(false, matches(tx("-9.98", paidAt)))

    @Test fun `exactly three days later matches`() = assertEquals(true, matches(tx("-9.99", paidAt.plus(Duration.ofDays(3)))))

    @Test fun `exactly three days earlier matches`() = assertEquals(true, matches(tx("-9.99", paidAt.minus(Duration.ofDays(3)))))

    @Test fun `one second past three days does not match`() =
        assertEquals(false, matches(tx("-9.99", paidAt.plus(Duration.ofDays(3)).plusSeconds(1))))

    @Test fun `a row the user entered is not a generated payment`() =
        assertEquals(false, matches(tx("-9.99", paidAt.plus(Duration.ofDays(1))), listOf(generated.copy(recurrenceRuleId = null))))

    @Test fun `one generated payment absorbs only one bank row`() {
        val (fresh, duplicates) = ImportReconciler.split(
            listOf(tx("-9.99", paidAt.plus(Duration.ofDays(1)), "A"), tx("-9.99", paidAt.plus(Duration.ofDays(2)), "B")),
            listOf(generated),
        )
        assertEquals(listOf("A"), duplicates.map { it.note })
        assertEquals(listOf("B"), fresh.map { it.note })
    }

    @Test fun `an exact copy of any row is a duplicate even without a rule`() {
        val manual = tx("-750.00", paidAt, note = "Rent")
        assertEquals(true, matches(tx("-750.0", paidAt, note = "Rent"), listOf(manual)))
        assertEquals(false, matches(tx("-750.00", paidAt, note = "Rent "), listOf(manual)))
    }
}
