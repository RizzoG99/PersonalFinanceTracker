package com.rizzog99.personalfinancetracker.features.activity

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTravelRepository
import com.rizzog99.personalfinancetracker.data.repository.TravelRepository
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.domain.transaction.TransactionTypeFilter
import com.rizzog99.personalfinancetracker.domain.travel.ActivityRow
import com.rizzog99.personalfinancetracker.domain.travel.FinanceTravel
import com.rizzog99.personalfinancetracker.features.insights.InsightsViewModel
import com.rizzog99.personalfinancetracker.features.states.FakePreferencesDataStore
import com.rizzog99.personalfinancetracker.features.travels.TravelsViewModel
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** #284 AC-01 / AC-04 / AC-06 through the view models, on a real (in-memory) Room store. Fixture T. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class ActivityTravelTest {
    private val zone = ZoneId.of("Europe/Rome")
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var categories: RoomCategoryRepository
    private lateinit var travels: RoomTravelRepository
    private lateinit var trip: FinanceTravel

    @Before
    fun setUp() = runBlocking {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        transactions = RoomTransactionRepository(database)
        categories = RoomCategoryRepository(database)
        travels = RoomTravelRepository(database)
        categories.seedDefaultsIfEmpty()
        travels.add("Montagna", "mountain.2")
        trip = travels.add("Barcellona", "airplane")
        transactions.upsertAll(
            listOf(
                row("Hotel", "12", "-250.00", trip.id),
                row("Taxi", "14", "-30.00", trip.id),
                row("Rimborso", "16", "50.00", trip.id),
                row("Caffè", "15", "-3.00"),
            ),
        )
    }

    @After
    fun tearDown() {
        database.close()
        Dispatchers.resetMain()
    }

    private fun row(id: String, day: String, amount: String, travel: String? = null) = FinanceTransaction(
        id = id, timestamp = Instant.parse("2026-09-${day}T10:00:00Z"), amount = BigDecimal(amount), note = id,
        categoryLabel = "Travel", categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null, travelId = travel,
    )

    private fun viewModel(travelRepository: TravelRepository = travels) =
        ActivityViewModel(transactions, categories, RoomRecurrenceRepository(database), zone, travelRepository)

    private suspend fun ActivityViewModel.await(what: String, predicate: (ActivityUiState) -> Boolean) =
        try {
            withTimeout(5_000) { uiState.first { !it.isLoading && predicate(it) } }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            throw AssertionError("never: $what", e)
        }

    private fun ActivityUiState.travelRows() = activityDays.flatMap { it.rows }.filterIsInstance<ActivityRow.Travel>()

    @Test
    fun ac01_travelsCollapseOnlyInThePlainList() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        val plain = vm.await("grouped") { it.travelRows().size == 1 }
        assertEquals(listOf("Barcellona"), plain.travelRows().map { it.summary.name })
        assertEquals(4, plain.visibleTransactions.size)

        vm.updateSearch("taxi")
        vm.await("search ungroups") { it.searchText == "taxi" && it.travelRows().isEmpty() && it.visibleTransactions.size == 1 }
        vm.updateSearch("")
        vm.await("regrouped") { it.travelRows().size == 1 }

        vm.updateTypeFilter(TransactionTypeFilter.EXPENSE)
        vm.await("a structured filter ungroups") { it.travelRows().isEmpty() }
        vm.updateTypeFilter(TransactionTypeFilter.ALL)
        vm.await("regrouped") { it.travelRows().size == 1 }

        vm.enterSelection()
        val selecting = vm.await("selection expands") { it.checkedIds == emptySet<String>() && it.travelRows().isEmpty() }
        assertEquals(4, selecting.activityDays.sumOf { it.rows.size })
        keep.cancel()
    }

    @Test
    fun ac04_moveAndRemoveFromSelection() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("Caffè")
        assertFalse(vm.await("one") { it.checkedIds == setOf("Caffè") }.selectionHasTravel)
        vm.toggleSelection("Taxi")
        assertTrue(vm.await("two") { it.checkedIds == setOf("Caffè", "Taxi") }.selectionHasTravel)

        assertTrue(vm.bulkSetTravel(setOf("Caffè"), trip.id))
        assertEquals(trip.id, transactions.observeAll().first().single { it.id == "Caffè" }.travelId)
        assertTrue(vm.bulkSetTravel(setOf("Caffè", "Taxi"), null))
        assertEquals(listOf(null, null), transactions.observeAll().first().filter { it.id in setOf("Caffè", "Taxi") }.map { it.travelId })

        assertTrue(vm.addTravelAndAssign(setOf("Caffè"), "Roma", "car"))
        val roma = travels.observeAll().first().single { it.name == "Roma" }
        assertEquals(roma.id, transactions.observeAll().first().single { it.id == "Caffè" }.travelId)
        keep.cancel()
    }

    @Test
    fun ac04_aBulkEditKeepsTheTravelTag() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("Hotel")
        vm.toggleSelection("Taxi")
        vm.await("two") { it.checkedIds == setOf("Hotel", "Taxi") }
        val result = vm.bulkSetAmount(BigDecimal("20"))!!
        val after = transactions.observeAll().first().filter { it.id in setOf("Hotel", "Taxi") }
        assertEquals(listOf(trip.id, trip.id), after.map { it.travelId })
        assertTrue(vm.restore(result.prior))
        assertEquals(listOf(trip.id, trip.id), transactions.observeAll().first().filter { it.id in setOf("Hotel", "Taxi") }.map { it.travelId })
        keep.cancel()
    }

    @Test
    fun ac04_aTravelReadFailureReportsAndNeverCrashes() = runBlocking {
        val failing = object : TravelRepository by TravelRepository.None {
            override fun observeAll(): Flow<List<FinanceTravel>> = flow { throw IllegalStateException("SQLITE /data/x.db") }
            override suspend fun add(name: String, symbolName: String): FinanceTravel = throw IllegalStateException("SQLITE /data/x.db")
        }
        val vm = viewModel(failing)
        val keep = launch { vm.uiState.collect {} }
        assertTrue(vm.await("error state") { it.isError }.isError)
        assertNull(vm.addTravel("Roma", "car"))
        assertEquals(R.string.activity_update_failed, vm.error.value)

        val travelsVm = TravelsViewModel(transactions, failing, categories, zone)
        val keep2 = launch { travelsVm.uiState.collect {} }
        assertTrue(withTimeout(5_000) { travelsVm.uiState.first { it.isError } }.isError)
        assertNull(travelsVm.add("Roma", "car"))
        assertEquals(R.string.activity_update_failed, travelsVm.error.value)
        keep.cancel()
        keep2.cancel()
    }

    /** Code review r1: "This and future" on a tagged occurrence keeps its travel. */
    @Test
    fun ac04_thisAndFutureKeepsTheTravel() = runBlocking {
        val recurrence = RoomRecurrenceRepository(database)
        recurrence.createAndMaterialize(
            com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule(
                frequency = com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency.MONTHLY, interval = 1,
                startDate = Instant.parse("2026-09-13T10:00:00Z"), amount = BigDecimal("-15.00"), note = "Hostel",
                categoryLabel = "Travel", categoryId = null, currencyCode = "EUR",
            ),
        )
        val occurrence = transactions.observeAll().first().first { it.note == "Hostel" }
        travels.assign(listOf(occurrence.id), trip.id)
        val vm = viewModel()
        assertTrue(vm.updateThisAndFuture(occurrence.copy(note = "Ostello", travelId = trip.id)))
        assertEquals(trip.id, transactions.observeAll().first().single { it.id == occurrence.id }.travelId)
    }

    @Test
    fun ac06_insightsAreUnchangedByTagging() = runBlocking {
        val clock = Clock.fixed(Instant.parse("2026-09-20T10:00:00Z"), zone)
        fun insights() = InsightsViewModel(
            transactions, RoomGoalRepository(database), UserPreferencesRepository(FakePreferencesDataStore()), categories, clock, zone,
        )
        suspend fun snapshot(vm: InsightsViewModel) = withTimeout(5_000) { vm.uiState.first { !it.isLoading } }.also {
            assertFalse("Insights loaded", it.isError)
            assertEquals(0, BigDecimal("50.00").compareTo(it.income))
            assertEquals(0, BigDecimal("283.00").compareTo(it.expenses))
        }

        val tagged = insights()
        val keep = launch { tagged.uiState.collect {} }
        val before = snapshot(tagged)
        keep.cancel()
        travels.assign(listOf("Caffè"), trip.id)
        travels.delete(trip.id)

        val after = insights()
        val keep2 = launch { after.uiState.collect {} }
        assertEquals(before, snapshot(after))
        keep2.cancel()
    }
}
