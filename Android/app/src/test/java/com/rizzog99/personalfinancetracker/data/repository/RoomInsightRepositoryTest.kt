package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.insight.DailyForecastCache
import com.rizzog99.personalfinancetracker.domain.insight.DayValue
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RoomInsightRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var repository: InsightRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = RoomInsightRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `AC-03_1 a health score snapshot round trips every field`() = runBlocking {
        val snapshot = snapshot(id = "snap-1", at = "2026-03-14T08:30:00Z", score = 72)

        repository.saveSnapshot(snapshot)

        assertEquals(snapshot, repository.recentSnapshots(limit = 10).single())
    }

    @Test
    fun `AC-03_2 snapshots come back newest first and honour the limit`() = runBlocking {
        repository.saveSnapshot(snapshot(id = "old", at = "2026-01-01T00:00:00Z", score = 40))
        repository.saveSnapshot(snapshot(id = "newest", at = "2026-03-01T00:00:00Z", score = 80))
        repository.saveSnapshot(snapshot(id = "middle", at = "2026-02-01T00:00:00Z", score = 60))

        assertEquals(
            listOf("newest", "middle", "old"),
            repository.recentSnapshots(limit = 10).map(HealthScoreSnapshot::id),
        )
        assertEquals(
            listOf("newest", "middle"),
            repository.recentSnapshots(limit = 2).map(HealthScoreSnapshot::id),
        )
    }

    @Test
    fun `AC-03_3 re-saving a snapshot id replaces it instead of duplicating`() = runBlocking {
        repository.saveSnapshot(snapshot(id = "today", at = "2026-03-14T08:30:00Z", score = 55))
        repository.saveSnapshot(snapshot(id = "today", at = "2026-03-14T21:05:00Z", score = 91))

        val stored = repository.recentSnapshots(limit = 10).single()
        assertEquals(91, stored.score)
        assertEquals(Instant.parse("2026-03-14T21:05:00Z"), stored.timestamp)
    }

    @Test
    fun `AC-04_1 a forecast cache round trips keys days and exact values`() = runBlocking {
        val cache = DailyForecastCache(
            monthKey = "2026-06",
            computedUpToDay = 17,
            dayValues = listOf(
                DayValue(1, BigDecimal("12.34")),
                DayValue(2, BigDecimal("98.76543210")),
                DayValue(17, BigDecimal("1234567890.000000001")),
            ),
        )

        repository.saveForecastCache(cache)

        val stored = requireNotNull(repository.forecastCache())
        assertEquals("2026-06", stored.monthKey)
        assertEquals(17, stored.computedUpToDay)
        assertEquals(listOf(1, 2, 17), stored.dayValues.map(DayValue::day))
        cache.dayValues.zip(stored.dayValues).forEach { (expected, actual) ->
            assertEquals(0, expected.amount.compareTo(actual.amount))
            assertEquals(expected.amount.stripTrailingZeros(), actual.amount.stripTrailingZeros())
        }
    }

    @Test
    fun `AC-04_2 saving a new month replaces the cached row`() = runBlocking {
        repository.saveForecastCache(
            DailyForecastCache("2026-06", 30, listOf(DayValue(1, BigDecimal("5.00")))),
        )
        repository.saveForecastCache(
            DailyForecastCache("2026-07", 3, listOf(DayValue(1, BigDecimal("7.25")))),
        )

        assertEquals(1, database.dailyForecastCacheDao().count())
        val stored = requireNotNull(repository.forecastCache())
        assertEquals("2026-07", stored.monthKey)
        assertEquals(3, stored.computedUpToDay)
        assertEquals(0, BigDecimal("7.25").compareTo(stored.dayValues.single().amount))
    }

    @Test
    fun `AC-04_3 an empty forecast cache reads back as null`() = runBlocking {
        assertNull(repository.forecastCache())

        repository.saveForecastCache(DailyForecastCache("2026-06", 1, listOf(DayValue(1, BigDecimal.ONE))))
        repository.clearForecastCache()

        assertNull(repository.forecastCache())
    }

    private fun snapshot(id: String, at: String, score: Int) = HealthScoreSnapshot(
        id = id,
        timestamp = Instant.parse(at),
        score = score,
        savingsScore = score - 1,
        stabilityScore = score - 2,
        adherenceScore = score - 3,
        subscriptionScore = score - 4,
    )
}
