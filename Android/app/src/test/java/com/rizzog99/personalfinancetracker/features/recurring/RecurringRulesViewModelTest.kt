package com.rizzog99.personalfinancetracker.features.recurring

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** #294 AC-01..05 through [RecurringRulesViewModel] on a real (in-memory) Room store. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class RecurringRulesViewModelTest {
    private val zone = ZoneId.of("Europe/Rome")
    private val now = Instant.parse("2026-11-21T11:00:00Z")
    private val clock = Clock.fixed(now, zone)
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var recurrence: RoomRecurrenceRepository
    private lateinit var categories: RoomCategoryRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        transactions = RoomTransactionRepository(database)
        recurrence = RoomRecurrenceRepository(database)
        categories = RoomCategoryRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
        Dispatchers.resetMain()
    }

    private fun at(date: String): Instant = LocalDate.parse(date).atTime(10, 0).atZone(zone).toInstant()

    private fun newRule(
        note: String,
        amount: String,
        start: String,
        frequency: RecurrenceFrequency = RecurrenceFrequency.MONTHLY,
        interval: Int = 1,
        autoRecord: Boolean = true,
    ) = NewRecurrenceRule(
        frequency = frequency, interval = interval, startDate = at(start), amount = BigDecimal(amount), note = note,
        categoryLabel = "Bills", categoryId = null, currencyCode = "EUR", autoRecord = autoRecord,
    )

    private fun viewModel(
        repository: RecurrenceRepository = recurrence,
        clock: Clock = this.clock,
    ) = RecurringRulesViewModel(repository, transactions, categories, clock)

    private suspend fun RecurringRulesViewModel.await(predicate: (RecurringRulesUiState) -> Boolean): RecurringRulesUiState =
        withTimeout(5_000) { uiState.first { !it.isLoading && predicate(it) } }

    private fun edited(rule: RecurrenceRule, amount: String, note: String, categoryId: String?, categoryLabel: String) = FinanceTransaction(
        id = rule.id, timestamp = rule.startDate, amount = BigDecimal(amount), note = note, categoryLabel = categoryLabel,
        categoryId = categoryId, currencyCode = "EUR", goalId = rule.goalId, recurrenceRuleId = null,
    )

    @Test
    fun ac01_listsActiveRulesWithStats() = runBlocking {
        recurrence.create(newRule("Netflix", "-12.99", "2026-01-05"))
        recurrence.create(newRule("Salary", "2000.00", "2026-01-27"))
        recurrence.create(newRule("Gym", "-30.00", "2026-11-10", RecurrenceFrequency.WEEKLY, interval = 2))
        val stopped = recurrence.create(newRule("Old gym", "-40.00", "2026-01-01"))
        recurrence.stop(stopped.id, now.minusSeconds(3_600))

        val state = viewModel().await { it.rows.size == 3 }

        assertEquals(3, state.activeCount)
        assertEquals(BigDecimal("-77.99"), state.monthlySpend)
        // By next due date: Gym 24 Nov, Salary 27 Nov, Netflix 5 Dec (D-07).
        assertEquals(listOf("Gym", "Salary", "Netflix"), state.rows.map { it.title })
        assertEquals(LocalDate.parse("2026-11-24"), state.rows.first().nextDate?.atZone(zone)?.toLocalDate())
    }

    @Test
    fun ac02_editsHistoryFreeForecastRule() = runBlocking {
        val planned = recurrence.createAll(listOf(newRule("Netflix", "-12.99", "2026-12-01", autoRecord = false))).single()
        val vm = viewModel()
        vm.await { it.rows.size == 1 }

        assertTrue(vm.saveRule(planned, edited(planned, "-15.99", "Netflix 4K", categoryId = null, categoryLabel = "Streaming")))

        val rule = vm.await { it.rows.singleOrNull()?.rule?.note == "Netflix 4K" }.rows.single().rule
        assertEquals(BigDecimal("-15.99"), rule.amount)
        assertEquals("Streaming", rule.categoryLabel)
        assertEquals(planned.copy(amount = rule.amount, note = rule.note, categoryLabel = rule.categoryLabel), rule)
        assertTrue(transactions.observeAll().first().isEmpty())
    }

    @Test
    fun ac02_editKeepsPastOccurrencesAndChangesTheNextOne() = runBlocking {
        val rule = recurrence.createAndMaterialize(newRule("Rent", "-750.00", "2026-09-01"))
        recurrence.materializeDue(now, zone)
        assertEquals(3, transactions.observeAll().first().size)
        val vm = viewModel()
        vm.await { it.rows.size == 1 }

        assertTrue(vm.saveRule(rule, edited(rule, "-780.00", "Rent", null, "Bills")))
        recurrence.materializeDue(at("2026-12-02"), zone)

        // MoneyCodec stores without trailing zeros, so compare values, not scales.
        val byDate = transactions.observeAll().first().associate { it.timestamp.atZone(zone).toLocalDate().toString() to it.amount.toDouble() }
        assertEquals(
            mapOf("2026-09-01" to -750.0, "2026-10-01" to -750.0, "2026-11-01" to -750.0, "2026-12-01" to -780.0),
            byDate,
        )
    }

    @Test
    fun ac03_stopKeepsHistoryAndSurvivesRelaunch() = runBlocking {
        val rule = recurrence.createAndMaterialize(newRule("Rent", "-750.00", "2026-09-01"))
        recurrence.materializeDue(now, zone)
        val october = transactions.observeAll().first().single { it.timestamp == at("2026-10-01") }
        transactions.delete(october.id) // "this transaction only"
        val written = CompletableDeferred<Unit>()
        val gate = CompletableDeferred<Unit>()
        val slowStop = object : RecurrenceRepository by recurrence {
            override suspend fun stop(id: String, at: Instant) {
                gate.await()
                recurrence.stop(id, at)
                written.complete(Unit)
            }
        }
        val vm = viewModel(slowStop)
        vm.await { it.rows.size == 1 }

        vm.stop(rule)
        // The row leaves before the write finishes (#253).
        vm.await { it.rows.isEmpty() }
        gate.complete(Unit)
        withTimeout(5_000) { written.await() }

        assertEquals(now, recurrence.observeAll().first().single().endDate)
        assertEquals(2, transactions.observeAll().first().size)

        // Relaunch a minute later: start-up materialization runs, the new screen reads the store.
        val later = Clock.offset(clock, java.time.Duration.ofMinutes(1))
        recurrence.materializeDue(at("2027-03-01"), zone)
        val relaunched = viewModel(clock = later).await { true }
        assertTrue(relaunched.rows.isEmpty())
        assertEquals(
            setOf(at("2026-09-01"), at("2026-11-01")),
            transactions.observeAll().first().map { it.timestamp }.toSet(),
        )
    }

    @Test
    fun ac03_failedStopBringsTheRowBack() = runBlocking {
        val rule = recurrence.create(newRule("Rent", "-750.00", "2026-09-01"))
        val failing = object : RecurrenceRepository by recurrence {
            override suspend fun stop(id: String, at: Instant) = error("disk full at /data/data/app/db")
        }
        val vm = viewModel(failing)
        vm.await { it.rows.size == 1 }

        vm.stop(rule)

        vm.await { it.rows.size == 1 }
        withTimeout(5_000) { vm.error.first { it != null } }
        assertEquals(R.string.activity_update_failed, vm.error.value)
        assertNull(recurrence.observeAll().first().single().endDate)
    }

    @Test
    fun ac04_emptyWhenOnlyStoppedRules() = runBlocking {
        val rule = recurrence.create(newRule("Rent", "-750.00", "2026-09-01"))
        recurrence.stop(rule.id, now.minusSeconds(60))
        // A rule appearing would prove the flow is live; there is none, so wait on the store first.
        assertEquals(1, recurrence.observeAll().first().size)

        val state = viewModel().await { true }

        assertTrue(state.rows.isEmpty())
        assertEquals(0, BigDecimal.ZERO.compareTo(state.monthlySpend))
    }

    @Test
    fun ac04_addCreatesRuleAndFirstOccurrence() = runBlocking {
        val vm = viewModel()
        val first = FinanceTransaction("t1", at("2026-11-21"), BigDecimal("-9.99"), "Music", "Bills", null, "EUR", null, null)

        assertTrue(vm.add(first, newRule("Music", "-9.99", "2026-11-21")))

        assertEquals(1, vm.await { it.rows.size == 1 }.rows.size)
        assertEquals(1, transactions.observeAll().first().size)
    }

    @Test
    fun ac04_receiptLearningFailureStillSaves() = runBlocking {
        val failingMapping = object : com.rizzog99.personalfinancetracker.data.repository.ReceiptMappingRepository {
            override suspend fun categoryIdFor(merchant: String): String? = null
            override suspend fun remember(merchant: String, categoryId: String) = error("disk full")
        }
        val vm = RecurringRulesViewModel(recurrence, transactions, categories, clock, failingMapping)
        val first = FinanceTransaction("t1", at("2026-11-21"), BigDecimal("-9.99"), "Music", "Bills", "bills", "EUR", null, null)

        assertTrue(vm.add(first, newRule("Music", "-9.99", "2026-11-21"), receiptMerchant = "Spotify"))

        assertNull(vm.error.value)
        assertEquals(1, transactions.observeAll().first().size)
    }

    @Test
    fun ac05_importPlannedRulesAppear() = runBlocking {
        recurrence.createAll(
            listOf(
                newRule("Affitto", "-750.00", "2026-12-01", autoRecord = false),
                newRule("Luce", "-62.10", "2026-12-05", autoRecord = false),
            ),
        )

        val state = viewModel().await { it.rows.size == 2 }

        assertEquals(listOf("Affitto", "Luce"), state.rows.map { it.title })
    }
}
