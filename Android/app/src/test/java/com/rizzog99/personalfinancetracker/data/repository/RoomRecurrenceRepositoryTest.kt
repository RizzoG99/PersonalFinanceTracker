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
}
