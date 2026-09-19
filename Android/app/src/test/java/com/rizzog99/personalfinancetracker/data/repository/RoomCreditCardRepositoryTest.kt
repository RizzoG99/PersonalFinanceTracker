package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.credit.CreditCard
import com.rizzog99.personalfinancetracker.domain.credit.NewCreditCard
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RoomCreditCardRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var repository: CreditCardRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = RoomCreditCardRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `AC-01_1 every frozen contract field round trips through the repository`() = runBlocking {
        val added = repository.add(
            NewCreditCard(
                name = "Revolving Visa",
                lastFour = "4291",
                balance = BigDecimal("1234.56"),
                limit = BigDecimal("5000.00"),
                colorToken = "accentTeal",
                currencyCode = "EUR",
            ),
        )

        val stored = requireNotNull(repository.get(added.id))
        assertEquals(added.id, stored.id)
        assertEquals("Revolving Visa", stored.name)
        assertEquals("4291", stored.lastFour)
        assertEquals(0, BigDecimal("1234.56").compareTo(stored.balance))
        assertEquals(0, BigDecimal("5000.00").compareTo(stored.limit))
        assertEquals("accentTeal", stored.colorToken)
        assertEquals("EUR", stored.currencyCode)
    }

    @Test
    fun `AC-01_2 balance and limit survive as exact decimals`() = runBlocking {
        val balance = BigDecimal("12345678901234567890.123456789")
        val limit = BigDecimal("99999999999999999999.000000001")

        val added = repository.add(
            NewCreditCard(name = "Precision", lastFour = "0001", balance = balance, limit = limit),
        )

        val stored = requireNotNull(repository.get(added.id))
        assertEquals(0, balance.compareTo(stored.balance))
        assertEquals(0, limit.compareTo(stored.limit))
        // compareTo alone would accept a rounded value of equal magnitude; scale proves exactness.
        assertEquals(balance.stripTrailingZeros(), stored.balance.stripTrailingZeros())
        assertEquals(limit.stripTrailingZeros(), stored.limit.stripTrailingZeros())
    }

    @Test
    fun `AC-01_3 update mutates in place and delete removes only the addressed card`() = runBlocking {
        val kept = repository.add(
            NewCreditCard(name = "Kept", lastFour = "1111", balance = BigDecimal("10.00"), limit = BigDecimal("100.00")),
        )
        val edited = repository.add(
            NewCreditCard(name = "Edited", lastFour = "2222", balance = BigDecimal("20.00"), limit = BigDecimal("200.00")),
        )

        repository.update(
            CreditCard(
                id = edited.id,
                name = "Renamed",
                lastFour = "3333",
                balance = BigDecimal("250.75"),
                limit = BigDecimal("900.00"),
                colorToken = "accentRose",
                currencyCode = "EUR",
            ),
        )

        assertEquals(2, repository.observeAll().first().size)
        val updated = requireNotNull(repository.get(edited.id))
        assertEquals("Renamed", updated.name)
        assertEquals("3333", updated.lastFour)
        assertEquals(0, BigDecimal("250.75").compareTo(updated.balance))
        assertEquals(0, BigDecimal("900.00").compareTo(updated.limit))
        assertEquals("accentRose", updated.colorToken)

        repository.delete(edited.id)
        assertNull(repository.get(edited.id))
        assertEquals(listOf(kept.id), repository.observeAll().first().map(CreditCard::id))
    }

    @Test
    fun `AC-01_4 cards are listed by name like the frozen sort descriptor`() = runBlocking {
        listOf("Zephyr", "amex", "Mastercard").forEachIndexed { index, name ->
            repository.add(
                NewCreditCard(
                    name = name,
                    lastFour = "000$index",
                    balance = BigDecimal.ZERO,
                    limit = BigDecimal("1000"),
                ),
            )
        }

        assertEquals(
            listOf("amex", "Mastercard", "Zephyr"),
            repository.observeAll().first().map(CreditCard::name),
        )
    }

    @Test
    fun `AC-02_1 deleting a card leaves every unrelated record untouched`() = runBlocking {
        val categoryRepository = RoomCategoryRepository(database)
        val goalRepository = RoomGoalRepository(database)
        val recurrenceRepository = RoomRecurrenceRepository(database)

        val category = categoryRepository.add(
            NewCategory(
                name = "Groceries",
                iconToken = "cart.fill",
                type = TransactionType.EXPENSE,
                colorToken = "categoryTeal",
                monthlyBudget = BigDecimal("300.00"),
                currencyCode = "EUR",
            ),
        )
        val goal = goalRepository.add(
            NewGoal(name = "Emergency fund", targetAmount = BigDecimal("2000.00")),
        )
        val rule = recurrenceRepository.createAndMaterialize(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY,
                interval = 1,
                startDate = Instant.parse("2026-01-15T09:00:00Z"),
                amount = BigDecimal("-45.90"),
                note = "Weekly shop",
                categoryLabel = "Groceries",
                categoryId = category.id,
                currencyCode = "EUR",
                goalId = goal.id,
            ),
        )
        val transactionsBefore = RoomTransactionRepository(database).observeAll().first()

        val card = repository.add(
            NewCreditCard(name = "Visa", lastFour = "4291", balance = BigDecimal("120.00"), limit = BigDecimal("3000.00")),
        )
        repository.delete(card.id)

        assertNull(repository.get(card.id))
        assertEquals(transactionsBefore, RoomTransactionRepository(database).observeAll().first())
        assertEquals(listOf(category.id), categoryRepository.observeAll().first().map { it.id })
        assertEquals(listOf(goal.id), goalRepository.observeAll().first().map { it.id })
        assertEquals(rule.id, requireNotNull(database.recurrenceRuleDao().get(rule.id)).id)
    }
}
