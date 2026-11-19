package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
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
class RoomRecurrenceRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var recurrenceRepository: RecurrenceRepository
    private lateinit var transactionRepository: TransactionRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        recurrenceRepository = RoomRecurrenceRepository(database)
        transactionRepository = RoomTransactionRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `creating a rule materializes its first occurrence and later runs catch up without duplicates`() = runBlocking {
        val start = Instant.parse("2026-01-31T10:00:00Z")
        val rule = recurrenceRepository.createAndMaterialize(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY,
                interval = 1,
                startDate = start,
                amount = BigDecimal("-9.99"),
                note = "Music subscription",
                categoryLabel = "Music",
                categoryId = null,
                currencyCode = "EUR",
            ),
        )

        assertEquals(listOf(start), transactionRepository.observeAll().first().map { it.timestamp })

        recurrenceRepository.materializeDue(
            through = Instant.parse("2026-03-31T10:00:00Z"),
            zoneId = ZoneOffset.UTC,
        )
        recurrenceRepository.materializeDue(
            through = Instant.parse("2026-03-31T10:00:00Z"),
            zoneId = ZoneOffset.UTC,
        )

        val occurrences = transactionRepository.observeAll().first()
        assertEquals(
            listOf(
                Instant.parse("2026-03-31T10:00:00Z"),
                Instant.parse("2026-02-28T10:00:00Z"),
                start,
            ),
            occurrences.map { it.timestamp },
        )
        assertEquals(listOf(rule.id), occurrences.mapNotNull { it.recurrenceRuleId }.distinct())
        assertEquals(
            Instant.parse("2026-03-31T10:00:00Z").toEpochMilli(),
            database.recurrenceRuleDao().get(rule.id)?.lastMaterializedDateEpochMillis,
        )
        assertNotNull(database.recurrenceRuleDao().get(rule.id))
    }

    /** A forecast-only fixed expense (#295 AC-03): planned from a payment that already happened. */
    private fun forecastRent(start: Instant) = NewRecurrenceRule(
        frequency = RecurrenceFrequency.MONTHLY,
        interval = 1,
        startDate = start,
        amount = BigDecimal("-750.00"),
        note = "Affitto",
        categoryLabel = "Rent",
        categoryId = null,
        currencyCode = "EUR",
        autoRecord = false,
        lastMaterializedDate = start,
    )

    @Test
    fun `ac03 a forecast-only rule never inserts and advances when a matching payment arrives`() = runBlocking {
        val start = Instant.parse("2026-11-01T12:00:00Z")
        val rule = recurrenceRepository.create(forecastRent(start))
        // The real bank payment, two days early and with a month in its note.
        transactionRepository.upsert(
            com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction(
                id = "paid-nov",
                timestamp = Instant.parse("2026-11-29T09:00:00Z"),
                amount = BigDecimal("-750.00"),
                note = "Affitto dicembre",
                categoryLabel = "Rent",
                categoryId = null,
                currencyCode = "EUR",
                goalId = null,
                recurrenceRuleId = null,
            ),
        )

        recurrenceRepository.materializeDue(through = Instant.parse("2026-12-03T12:00:00Z"), zoneId = ZoneOffset.UTC)

        val all = transactionRepository.observeAll().first()
        assertEquals("a forecast-only rule must not insert rows", emptyList<String>(), all.mapNotNull { it.recurrenceRuleId })
        assertEquals(listOf("paid-nov"), all.map { it.id })
        assertEquals(
            Instant.parse("2026-12-01T12:00:00Z").toEpochMilli(),
            database.recurrenceRuleDao().get(rule.id)?.lastMaterializedDateEpochMillis,
        )
        assertEquals(false, database.recurrenceRuleDao().get(rule.id)?.autoRecord)
    }

    @Test
    fun `ac03 a forecast-only rule created through createAndMaterialize inserts nothing`() = runBlocking {
        recurrenceRepository.createAndMaterialize(forecastRent(Instant.parse("2026-11-01T12:00:00Z")).copy(lastMaterializedDate = null))

        assertEquals(emptyList<Any>(), transactionRepository.observeAll().first())
    }

    @Test
    fun `editing this and future preserves the edited occurrence and rebuilds later ones from the new template`() = runBlocking {
        val start = Instant.parse("2026-01-31T10:00:00Z")
        recurrenceRepository.createAndMaterialize(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY,
                interval = 1,
                startDate = start,
                amount = BigDecimal("-9.99"),
                note = "Music subscription",
                categoryLabel = "Music",
                categoryId = null,
                currencyCode = "EUR",
            ),
        )
        val through = Instant.parse("2026-03-31T10:00:00Z")
        recurrenceRepository.materializeDue(through, ZoneOffset.UTC)
        val february = transactionRepository.observeAll().first().single {
            it.timestamp == Instant.parse("2026-02-28T10:00:00Z")
        }

        recurrenceRepository.updateThisAndFuture(february.copy(amount = BigDecimal("-12.99"), note = "Premium music"))
        recurrenceRepository.materializeDue(through, ZoneOffset.UTC)

        val occurrences = transactionRepository.observeAll().first()
        assertEquals(3, occurrences.size)
        assertEquals(
            BigDecimal("-12.99"),
            occurrences.single { it.timestamp == Instant.parse("2026-02-28T10:00:00Z") }.amount,
        )
        assertEquals(
            BigDecimal("-12.99"),
            occurrences.single { it.timestamp == through }.amount,
        )
        assertEquals(
            "Premium music",
            occurrences.single { it.timestamp == through }.note,
        )
    }
}
