package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.room.withTransaction
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.credit.CreditCard
import com.rizzog99.personalfinancetracker.domain.credit.NewCreditCard
import com.rizzog99.personalfinancetracker.domain.insight.DailyForecastCache
import com.rizzog99.personalfinancetracker.domain.insight.DayValue
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * File-backed rather than in-memory: reopen durability is the whole point, and an in-memory
 * database cannot prove it.
 */
@RunWith(RobolectricTestRunner::class)
class RoomAdvancedPersistenceDurabilityTest {
    private lateinit var context: Context
    private var database: PersonalFinanceDatabase? = null
    private val databaseName = "m1-data-adv-durability.db"

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
    fun `AC-01_5 AC-03_4 AC-04_4 and AC-05_6 all four advanced record types survive close and reopen`() = runBlocking {
        database = openDatabase()
        val card = RoomCreditCardRepository(requireNotNull(database)).add(
            NewCreditCard(
                name = "Revolving Visa",
                lastFour = "4291",
                balance = BigDecimal("12345678901234567890.123456789"),
                limit = BigDecimal("99999999999999999999.000000001"),
                colorToken = "accentTeal",
                currencyCode = "EUR",
            ),
        )
        val insights = RoomInsightRepository(requireNotNull(database))
        val older = HealthScoreSnapshot(
            id = "older",
            timestamp = Instant.parse("2026-02-01T10:00:00Z"),
            score = 61,
            savingsScore = 55,
            stabilityScore = 70,
            adherenceScore = 48,
            subscriptionScore = 80,
        )
        val newer = older.copy(id = "newer", timestamp = Instant.parse("2026-03-01T10:00:00Z"), score = 74)
        insights.saveSnapshot(older)
        insights.saveSnapshot(newer)
        val forecast = DailyForecastCache(
            monthKey = "2026-03",
            computedUpToDay = 21,
            dayValues = listOf(
                DayValue(1, BigDecimal("10.05")),
                DayValue(21, BigDecimal("987654321.000000001")),
            ),
        )
        insights.saveForecastCache(forecast)
        RoomReceiptMappingRepository(requireNotNull(database)).apply {
            remember("  Caffè Roma  ", "coffee")
            remember("CAFFE ROMA", "restaurants")
        }

        database?.close()
        database = openDatabase()

        val reopenedCard = RoomCreditCardRepository(requireNotNull(database)).observeAll().first().single()
        assertEquals(card.id, reopenedCard.id)
        assertEquals(card.name, reopenedCard.name)
        assertEquals(card.lastFour, reopenedCard.lastFour)
        assertEquals(0, card.balance.compareTo(reopenedCard.balance))
        assertEquals(0, card.limit.compareTo(reopenedCard.limit))
        assertEquals(card.colorToken, reopenedCard.colorToken)
        assertEquals(card.currencyCode, reopenedCard.currencyCode)

        val reopenedInsights = RoomInsightRepository(requireNotNull(database))
        assertEquals(listOf(newer, older), reopenedInsights.recentSnapshots(limit = 10))

        val reopenedForecast = requireNotNull(reopenedInsights.forecastCache())
        assertEquals(forecast.monthKey, reopenedForecast.monthKey)
        assertEquals(forecast.computedUpToDay, reopenedForecast.computedUpToDay)
        assertEquals(forecast.dayValues.map(DayValue::day), reopenedForecast.dayValues.map(DayValue::day))
        forecast.dayValues.zip(reopenedForecast.dayValues).forEach { (expected, actual) ->
            assertEquals(0, expected.amount.compareTo(actual.amount))
        }

        val reopenedMappings = RoomReceiptMappingRepository(requireNotNull(database))
        assertEquals("coffee", reopenedMappings.categoryIdFor("caffè roma"))
        assertEquals("restaurants", reopenedMappings.categoryIdFor("caffe roma"))
    }

    @Test
    fun `AC-06 a failing batch write leaves no partial advanced records`() = runBlocking {
        database = openDatabase()
        val db = requireNotNull(database)
        val cards = RoomCreditCardRepository(db)
        val insights = RoomInsightRepository(db)
        val mappings = RoomReceiptMappingRepository(db)

        val survivor = cards.add(
            NewCreditCard(name = "Survivor", lastFour = "0000", balance = BigDecimal("1.00"), limit = BigDecimal("10.00")),
        )

        try {
            db.withTransaction {
                cards.add(
                    NewCreditCard(name = "Doomed", lastFour = "9999", balance = BigDecimal("2.00"), limit = BigDecimal("20.00")),
                )
                insights.saveSnapshot(
                    HealthScoreSnapshot(
                        id = "doomed",
                        timestamp = Instant.parse("2026-04-01T00:00:00Z"),
                        score = 50,
                        savingsScore = 50,
                        stabilityScore = 50,
                        adherenceScore = 50,
                        subscriptionScore = 50,
                    ),
                )
                insights.saveForecastCache(
                    DailyForecastCache("2026-04", 1, listOf(DayValue(1, BigDecimal("3.00")))),
                )
                mappings.remember("Doomed Merchant", "doomed-category")

                // Pins that the four writes actually landed on this transaction's connection.
                // Without it the rollback assertions below would also pass against writes that
                // silently never happened.
                assertEquals(2, cards.observeAll().first().size)
                assertEquals("doomed", insights.recentSnapshots(limit = 10).single().id)
                assertEquals("2026-04", requireNotNull(insights.forecastCache()).monthKey)
                assertEquals("doomed-category", mappings.categoryIdFor("Doomed Merchant"))

                error("batch write failed")
            }
        } catch (expected: IllegalStateException) {
            assertTrue(expected.message?.contains("batch write failed") == true)
        }

        assertEquals(listOf(survivor.id), cards.observeAll().first().map(CreditCard::id))
        assertEquals(emptyList<HealthScoreSnapshot>(), insights.recentSnapshots(limit = 10))
        assertNull(insights.forecastCache())
        assertNull(mappings.categoryIdFor("Doomed Merchant"))
    }

    private fun openDatabase(): PersonalFinanceDatabase = Room.databaseBuilder(
        context,
        PersonalFinanceDatabase::class.java,
        databaseName,
    )
        .allowMainThreadQueries()
        .build()
}
