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
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RoomCorePersistenceDurabilityTest {
    private lateinit var context: Context
    private var database: PersonalFinanceDatabase? = null
    private val databaseName = "m1-data-core-durability.db"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(databaseName)
    }

    @After
    fun tearDown() {
        database?.close()
        context.deleteDatabase(databaseName)
    }

    @Test
    fun `AC-06 AC-07 and AC-08 all core records and relationships survive close and reopen`() = runBlocking {
        database = openDatabase()
        val categoryRepository = RoomCategoryRepository(requireNotNull(database))
        val goalRepository = RoomGoalRepository(requireNotNull(database))
        val recurrenceRepository = RoomRecurrenceRepository(requireNotNull(database))

        val category = categoryRepository.add(
            NewCategory(
                name = "Long-term travel",
                iconToken = "airplane",
                type = TransactionType.EXPENSE,
                colorToken = "categoryTeal",
                monthlyBudget = BigDecimal("12345678901234567890.123456789"),
                currencyCode = "EUR",
            ),
        )
        val goal = goalRepository.add(
            NewGoal(
                name = "Round-the-world trip",
                targetAmount = BigDecimal("99999999999999999999.000000001"),
                deadline = Instant.parse("2099-12-31T23:59:59Z"),
                colorToken = "categoryAmber",
                iconToken = "globe.europe.africa.fill",
            ),
        )
        val rule = recurrenceRepository.createAndMaterialize(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.YEARLY,
                interval = 2,
                startDate = Instant.parse("2026-02-28T23:30:00Z"),
                amount = BigDecimal("-9876543210.000000001"),
                note = "Travel deposit",
                categoryLabel = "Travel snapshot",
                categoryId = category.id,
                currencyCode = "EUR",
                goalId = goal.id,
            ),
        )

        database?.close()
        database = openDatabase()

        val reopenedCategory = RoomCategoryRepository(requireNotNull(database)).observeAll().first().single()
        assertEquals(category.id, reopenedCategory.id)
        assertEquals(category.name, reopenedCategory.name)
        assertEquals(category.iconToken, reopenedCategory.iconToken)
        assertEquals(category.type, reopenedCategory.type)
        assertEquals(category.colorToken, reopenedCategory.colorToken)
        assertEquals(0, category.monthlyBudget!!.compareTo(reopenedCategory.monthlyBudget))
        assertEquals(category.currencyCode, reopenedCategory.currencyCode)

        val reopenedGoal = RoomGoalRepository(requireNotNull(database)).observeAll().first().single()
        assertEquals(goal.id, reopenedGoal.id)
        assertEquals(goal.name, reopenedGoal.name)
        assertEquals(0, goal.targetAmount.compareTo(reopenedGoal.targetAmount))
        assertEquals(goal.deadline, reopenedGoal.deadline)
        assertEquals(goal.colorToken, reopenedGoal.colorToken)
        assertEquals(goal.iconToken, reopenedGoal.iconToken)
        assertEquals(goal.createdAt, reopenedGoal.createdAt)

        val reopenedRule = requireNotNull(requireNotNull(database).recurrenceRuleDao().get(rule.id))
        assertEquals(rule.id, reopenedRule.id)
        assertEquals("yearly", reopenedRule.frequency)
        assertEquals(2, reopenedRule.interval)
        assertEquals(rule.startDate.toEpochMilli(), reopenedRule.startDateEpochMillis)
        assertEquals(rule.startDate.toEpochMilli(), reopenedRule.lastMaterializedDateEpochMillis)
        assertEquals(0, rule.amount.compareTo(reopenedRule.amountDecimal.toBigDecimal()))
        assertEquals(rule.note, reopenedRule.note)
        assertEquals(rule.categoryLabel, reopenedRule.categoryLabel)
        assertEquals(category.id, reopenedRule.categoryId)
        assertEquals(goal.id, reopenedRule.goalId)

        val reopenedTransaction = RoomTransactionRepository(requireNotNull(database)).observeAll().first().single()
        assertNotNull(reopenedTransaction.id)
        assertEquals(rule.startDate, reopenedTransaction.timestamp)
        assertEquals(0, rule.amount.compareTo(reopenedTransaction.amount))
        assertEquals(rule.note, reopenedTransaction.note)
        assertEquals(rule.categoryLabel, reopenedTransaction.categoryLabel)
        assertEquals(category.id, reopenedTransaction.categoryId)
        assertEquals(goal.id, reopenedTransaction.goalId)
        assertEquals(rule.id, reopenedTransaction.recurrenceRuleId)
        assertEquals(rule.currencyCode, reopenedTransaction.currencyCode)
    }

    private fun openDatabase(): PersonalFinanceDatabase = Room.databaseBuilder(
        context,
        PersonalFinanceDatabase::class.java,
        databaseName,
    )
        .allowMainThreadQueries()
        .build()
}
