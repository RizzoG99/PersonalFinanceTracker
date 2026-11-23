package com.rizzog99.personalfinancetracker.features.activity

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** #285 AC-02 / AC-04: the per-row rules of a bulk edit, as frozen iOS `TransactionListViewModel.swift:900-932`. */
class BulkEditRulesTest {
    private val expense = FinanceTransaction(
        id = "t2", timestamp = Instant.parse("2026-03-13T10:00:00Z"), amount = BigDecimal("-12.50"), note = "Caffè casa",
        categoryLabel = "Groceries", categoryId = "groceries", currencyCode = "EUR", goalId = "g1", recurrenceRuleId = "r1",
    )
    private val income = expense.copy(id = "t4", amount = BigDecimal("1500.00"), categoryLabel = "Salary", categoryId = "salary", goalId = null)

    private fun category(type: TransactionType, name: String) = FinanceCategory(
        id = name.lowercase(), name = name, iconToken = "x", type = type, colorToken = "categoryGray",
        monthlyBudget = null, currencyCode = "EUR",
    )

    @Test
    fun ac02_categoryFlipsSignToItsTypeAndClearsGoal() {
        val salary = category(TransactionType.INCOME, "Salary")
        val edited = expense.withBulkCategory(salary)
        assertEquals(0, BigDecimal("12.50").compareTo(edited.amount))
        assertEquals("Salary", edited.categoryLabel)
        assertEquals("salary", edited.categoryId)
        assertNull(edited.goalId)
        assertEquals(expense.copy(amount = edited.amount, categoryLabel = "Salary", categoryId = "salary", goalId = null), edited)

        val toExpense = income.withBulkCategory(category(TransactionType.EXPENSE, "Groceries"))
        assertEquals(0, BigDecimal("-1500.00").compareTo(toExpense.amount))
        // Already the right sign: stays.
        assertEquals(0, BigDecimal("-12.50").compareTo(expense.withBulkCategory(category(TransactionType.EXPENSE, "Gas")).amount))
    }

    @Test
    fun ac04_amountKeepsEachRowsSign() {
        assertEquals(0, BigDecimal("-20").compareTo(expense.withBulkAmount(BigDecimal("20")).amount))
        assertEquals(0, BigDecimal("20").compareTo(income.withBulkAmount(BigDecimal("20")).amount))
        assertEquals(0, BigDecimal("-20").compareTo(expense.withBulkAmount(BigDecimal("-20")).amount))
        assertEquals(expense.copy(amount = BigDecimal("-20")), expense.withBulkAmount(BigDecimal("20")))
    }

    @Test
    fun ac04_noteReplacesOnlyTheNote() {
        assertEquals(expense.copy(note = "Spesa"), expense.withBulkNote("Spesa"))
    }

    @Test
    fun ac04_setIsEnabledOnlyForAPositiveAmount() {
        listOf("", " ", "0", "0,00", "-3", "abc").forEach { assertFalse("'$it'", isValidBulkAmount(it)) }
        listOf("20", "12,5", "0.01").forEach { assertTrue("'$it'", isValidBulkAmount(it)) }
        assertEquals(0, BigDecimal("12.5").compareTo(parseBulkAmount("12,5")))
    }
}
