package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** #292 AC-02: the repair fixes what is certain and leaves everything else exactly as it was. */
@RunWith(RobolectricTestRunner::class)
class CategoryLinkRepairTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var categories: RoomCategoryRepository
    private lateinit var transactions: RoomTransactionRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        categories = RoomCategoryRepository(database)
        transactions = RoomTransactionRepository(database)
    }

    @After
    fun tearDown() = database.close()

    @Test
    fun ac02_repairIsIdempotentAndNeverGuessesAcrossTypes() = runBlocking {
        categories.seedDefaultsIfEmpty()
        val all = categories.observeAll().first()
        val groceries = all.single { it.name == "Groceries" && it.type == TransactionType.EXPENSE }
        val otherExpense = all.single { it.name == "Other" && it.type == TransactionType.EXPENSE }
        assertEquals(null, all.firstOrNull { it.name == "Groceries" && it.type == TransactionType.INCOME })
        val caffe = categories.add(NewCategory(name = "Caffè", iconToken = "cup", type = TransactionType.EXPENSE))
        val holiday = RoomGoalRepository(database).add(NewGoal("Holiday", BigDecimal("900.00"), null, "categoryIndigo", "star.fill"))
        transactions.insertBatch(
            listOf(
                tx("a", "-1.00", "Old", groceries.id),
                tx("b", "-3.00", "groceries ", null),
                tx("c", "4.00", "Groceries", null),
                tx("d", "-5.00", "Sconosciuta", null),
                // A goal transfer whose label would otherwise match: only the goal guard keeps it out.
                tx("e", "-6.00", "Groceries", null, goalId = holiday.id),
                tx("f", "-7.00", "", null),
                tx("g", "-9.00", "CAFFÈ\t", null),
            ),
        )
        val rule = RoomRecurrenceRepository(database).create(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = Instant.parse("2026-09-01T10:00:00Z"),
                amount = BigDecimal("-8.00"), note = "Box", categoryLabel = "groceries", categoryId = null,
                currencyCode = "EUR", autoRecord = false,
            ),
        )
        val goalRule = RoomRecurrenceRepository(database).create(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = Instant.parse("2026-09-01T10:00:00Z"),
                amount = BigDecimal("-8.50"), note = "Save", categoryLabel = "groceries", categoryId = null,
                currencyCode = "EUR", goalId = holiday.id, autoRecord = false,
            ),
        )

        // Links: b, f, g and the rule (4); labels: a, b, f, g and the rule (5).
        assertEquals(9, categories.repairLinks())

        val byId = transactions.observeAll().first().associate { it.id to (it.categoryId to it.categoryLabel) }
        assertEquals(groceries.id to "Groceries", byId["a"])
        assertEquals(groceries.id to "Groceries", byId["b"])
        assertEquals(null to "Groceries", byId["c"])
        assertEquals(null to "Sconosciuta", byId["d"])
        assertEquals(null to "Groceries", byId["e"])
        assertEquals(null, database.recurrenceRuleDao().get(goalRule.id)!!.categoryId)
        assertEquals(otherExpense.id to "Other", byId["f"])
        assertEquals(caffe.id to "Caffè", byId["g"])
        val repairedRule = database.recurrenceRuleDao().get(rule.id)!!
        assertEquals(groceries.id to "Groceries", repairedRule.categoryId to repairedRule.categoryLabel)

        assertEquals(0, categories.repairLinks())
        assertEquals(byId, transactions.observeAll().first().associate { it.id to (it.categoryId to it.categoryLabel) })
    }

    private fun tx(id: String, amount: String, label: String, categoryId: String?, goalId: String? = null) = FinanceTransaction(
        id = id, timestamp = Instant.parse("2026-10-15T09:00:00Z"), amount = BigDecimal(amount), note = "",
        categoryLabel = label, categoryId = categoryId, currencyCode = "EUR", goalId = goalId, recurrenceRuleId = null,
    )
}
