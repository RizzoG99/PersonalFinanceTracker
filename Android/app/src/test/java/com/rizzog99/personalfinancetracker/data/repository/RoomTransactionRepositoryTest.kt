package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.local.RecurrenceRuleEntity
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
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

    @Test
    fun `AC-01 and AC-02 exact signed amounts survive CRUD mapping in timestamp order`() = runBlocking {
        val fixtures = listOf(
            transaction(id = "positive", timestamp = "2026-09-05T10:00:00Z", amount = "1234567890123456789012345678.123456789"),
            transaction(id = "negative", timestamp = "2026-09-04T10:00:00Z", amount = "-987654321098765432109876543.000000001"),
            transaction(id = "zero", timestamp = "2026-09-03T10:00:00Z", amount = "0"),
            transaction(id = "fractional", timestamp = "2026-09-02T10:00:00Z", amount = "0.000000000000000001"),
        )

        repository.insertBatch(fixtures)

        val persisted = repository.observeAll().first()
        assertEquals(fixtures.map(FinanceTransaction::id), persisted.map(FinanceTransaction::id))
        fixtures.forEach { expected ->
            assertEquals(0, expected.amount.compareTo(persisted.single { it.id == expected.id }.amount))
        }

        val updated = persisted.single { it.id == "negative" }.copy(
            timestamp = Instant.parse("2026-09-06T10:00:00Z"),
            amount = BigDecimal("-0.000000000000000001"),
            note = "Updated note",
            categoryLabel = "Updated snapshot",
            currencyCode = "USD",
        )
        repository.upsert(updated)

        val mapped = repository.observeAll().first().first()
        assertEquals(updated.id, mapped.id)
        assertEquals(updated.timestamp, mapped.timestamp)
        assertEquals(0, updated.amount.compareTo(mapped.amount))
        assertEquals(updated.note, mapped.note)
        assertEquals(updated.categoryLabel, mapped.categoryLabel)
        assertEquals(updated.currencyCode, mapped.currencyCode)

        repository.delete(updated.id)
        assertNull(repository.observeAll().first().find { it.id == updated.id })
    }

    @Test
    fun `AC-03 batch insertion rolls back every new row when one row conflicts`() = runBlocking {
        repository.upsert(transaction(id = "existing", timestamp = "2026-09-01T10:00:00Z", amount = "1"))

        try {
            repository.insertBatch(
                listOf(
                    transaction(id = "would-have-been-inserted", timestamp = "2026-09-02T10:00:00Z", amount = "2"),
                    transaction(id = "existing", timestamp = "2026-09-03T10:00:00Z", amount = "3"),
                ),
            )
            fail("Expected the conflicting batch to abort")
        } catch (_: android.database.sqlite.SQLiteConstraintException) {
            // Expected: the unique primary-key conflict must roll back the entire transaction.
        }

        val persisted = repository.observeAll().first()
        assertEquals(listOf("existing"), persisted.map(FinanceTransaction::id))
        assertEquals(0, BigDecimal.ONE.compareTo(persisted.single().amount))
    }

    @Test
    fun `deleting this and future preserves prior occurrences and closes the rule`() = runBlocking {
        database.recurrenceRuleDao().insert(
            RecurrenceRuleEntity(
                id = "rule",
                frequency = "monthly",
                interval = 1,
                startDateEpochMillis = Instant.parse("2026-01-01T00:00:00Z").toEpochMilli(),
                endDateEpochMillis = null,
                lastMaterializedDateEpochMillis = null,
                amountDecimal = "-10",
                note = "Subscription",
                categoryLabel = "Music",
                categoryId = null,
                currencyCode = "EUR",
                goalId = null,
            ),
        )
        repository.insertBatch(
            listOf(
                transaction(id = "before", timestamp = "2026-01-01T10:00:00Z", amount = "-10", recurrenceRuleId = "rule"),
                transaction(id = "cutoff", timestamp = "2026-02-01T10:00:00Z", amount = "-10", recurrenceRuleId = "rule"),
                transaction(id = "future", timestamp = "2026-03-01T10:00:00Z", amount = "-10", recurrenceRuleId = "rule"),
            ),
        )

        repository.deleteThisAndFuture("rule", Instant.parse("2026-02-01T10:00:00Z"))

        assertEquals(listOf("before"), repository.observeAll().first().map(FinanceTransaction::id))
        assertEquals(
            Instant.parse("2026-02-01T10:00:00Z").minusMillis(1).toEpochMilli(),
            database.recurrenceRuleDao().get("rule")?.endDateEpochMillis,
        )
    }

    private fun transaction(id: String, timestamp: String, amount: String, recurrenceRuleId: String? = null) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse(timestamp),
        amount = BigDecimal(amount),
        note = "Test transaction",
        categoryLabel = "☕ Coffee",
        categoryId = null,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = recurrenceRuleId,
    )
}
