package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
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

@RunWith(RobolectricTestRunner::class)
class RoomTransactionRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var repository: TransactionRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = RoomTransactionRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `batch insert persists ordered transactions with exact decimal amounts`() = runBlocking {
        repository.insertBatch(
            listOf(
                transaction(id = "older", timestamp = "2026-09-01T10:00:00Z", amount = "-19.990"),
                transaction(id = "newer", timestamp = "2026-09-02T10:00:00Z", amount = "1200.10"),
            ),
        )

        assertEquals(
            listOf("newer", "older"),
            repository.observeAll().first().map(FinanceTransaction::id),
        )
        assertEquals(
            BigDecimal("-19.99"),
            repository.observeAll().first().single { it.id == "older" }.amount,
        )
    }

    private fun transaction(id: String, timestamp: String, amount: String) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse(timestamp),
        amount = BigDecimal(amount),
        note = "Test transaction",
        categoryLabel = "☕ Coffee",
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = null,
    )
}
