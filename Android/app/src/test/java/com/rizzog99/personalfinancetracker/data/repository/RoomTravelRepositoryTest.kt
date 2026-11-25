package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.io.File
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** #284 AC-03 / AC-04 persistence, against frozen iOS `TransactionActor` travel methods. */
@RunWith(RobolectricTestRunner::class)
class RoomTravelRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var travels: RoomTravelRepository
    private lateinit var transactions: RoomTransactionRepository
    private var now = Instant.parse("2026-09-01T08:00:00Z")
    private val clock = object : Clock() {
        override fun getZone() = ZoneOffset.UTC
        override fun withZone(zone: java.time.ZoneId?) = this
        override fun instant() = now
    }

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        travels = RoomTravelRepository(database, clock)
        transactions = RoomTransactionRepository(database)
    }

    @After
    fun tearDown() = database.close()

    private fun row(id: String, travel: String? = null) = FinanceTransaction(
        id = id, timestamp = Instant.parse("2026-09-12T10:00:00Z"), amount = BigDecimal("-10.00"), note = id,
        categoryLabel = "Travel", categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null, travelId = travel,
    )

    private suspend fun stored() = transactions.observeAll().first().associateBy { it.id }

    @Test
    fun `AC-03 add, rename and list newest first`() = runBlocking {
        val first = travels.add("  Barcellona ", "airplane")
        now = now.plusSeconds(60)
        val second = travels.add("Montagna", "mountain.2")
        assertEquals("Barcellona", first.name)
        assertEquals(listOf(second.id, first.id), travels.observeAll().first().map { it.id })

        travels.update(first.id, "Barcelona", "beach.umbrella")
        val renamed = travels.observeAll().first().single { it.id == first.id }
        assertEquals("Barcelona" to "beach.umbrella", renamed.name to renamed.symbolName)
        assertEquals(first.createdAt, renamed.createdAt)
    }

    @Test
    fun `AC-03 deleting a travel keeps its expenses and untags them`() = runBlocking {
        val trip = travels.add("Barcellona", "airplane")
        transactions.upsertAll(listOf(row("a", trip.id), row("b", trip.id), row("c")))

        travels.delete(trip.id)

        assertEquals(emptyList<Any>(), travels.observeAll().first())
        val after = stored()
        assertEquals(setOf("a", "b", "c"), after.keys)
        assertEquals(listOf(null, null, null), after.values.map { it.travelId })
    }

    @Test
    fun `AC-04 assign tags a batch and null untags it`() = runBlocking {
        val trip = travels.add("Barcellona", "airplane")
        val many = (1..1200).map { row("t$it") }
        transactions.upsertAll(many + row("keep"))

        travels.assign(many.map { it.id }, trip.id)
        assertEquals(1200, stored().values.count { it.travelId == trip.id })
        assertNull(stored().getValue("keep").travelId)

        travels.assign(listOf("t1", "t2"), null)
        assertEquals(1198, stored().values.count { it.travelId == trip.id })
    }

    @Test
    fun `AC-04 create and assign in one step`() = runBlocking {
        transactions.upsertAll(listOf(row("a"), row("b")))
        val trip = travels.addAndAssign("Lisbona", "tram", listOf("a", "b"))
        assertEquals(listOf(trip), travels.observeAll().first())
        assertEquals(listOf(trip.id, trip.id), stored().values.map { it.travelId })
    }

    @Test
    fun `AC-04 the tag survives closing and reopening the store`() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val file = File(context.cacheDir, "travel-restart.db").apply { delete() }
        fun open() = Room.databaseBuilder(context, PersonalFinanceDatabase::class.java, file.absolutePath).allowMainThreadQueries().build()

        var db = open()
        val trip = RoomTravelRepository(db, clock).add("Barcellona", "airplane")
        RoomTransactionRepository(db).upsertAll(listOf(row("a", trip.id)))
        db.close()

        db = open()
        assertEquals(trip.id, RoomTransactionRepository(db).observeAll().first().single().travelId)
        assertEquals(listOf("Barcellona"), RoomTravelRepository(db, clock).observeAll().first().map { it.name })
        db.close()
        file.delete()
        Unit
    }
}
