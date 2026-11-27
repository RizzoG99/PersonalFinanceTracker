package com.rizzog99.personalfinancetracker.features.insights

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.InsightRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.insight.DailyForecastCache
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.domain.insights.HealthComponentKind
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.states.FakeCategoryRepository
import com.rizzog99.personalfinancetracker.features.states.FakeGoalRepository
import com.rizzog99.personalfinancetracker.features.states.FakePreferencesDataStore
import com.rizzog99.personalfinancetracker.features.states.FakeTransactionRepository
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** #304 AC-02 and AC-04 through the view model: the stored switch, and one snapshot per day. */
@OptIn(ExperimentalCoroutinesApi::class)
class HealthScoreViewModelTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val zone = ZoneId.of("Europe/Rome")

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun at(m: Int, d: Int, h: Int = 12): Instant = LocalDateTime.of(2026, m, d, h, 0).atZone(zone).toInstant()
    private fun tx(id: String, amount: String, label: String, day: Instant) =
        FinanceTransaction(id, day, BigDecimal(amount), "", label, null, "EUR", null, null)

    /** Fixture H of the issue (see FinancialHealthTest). */
    private val fixture = (4..9).map { tx("salary-$it", "1200", "Salary", at(it, 1)) } + listOf(
        tx("apr", "-1000", "Rent", at(4, 5)), tx("may", "-1200", "Rent", at(5, 5)), tx("jun", "-800", "Rent", at(6, 5)),
        tx("jul", "-1000", "Rent", at(7, 5)), tx("aug-rent", "-770", "Rent", at(8, 5)), tx("aug-stream", "-30", "Streaming", at(8, 20)),
        tx("aug-last", "-600", "Car repair", at(8, 31, 18)), tx("groceries", "-250", "Groceries", at(9, 3)),
        tx("dining", "-150", "Dining", at(9, 4)), tx("sep-stream", "-30", "Streaming", at(9, 10)), tx("sep-other", "-170", "Pharmacy", at(9, 12)),
    )
    private val budgets = listOf("Groceries" to "300", "Dining" to "100").map { (name, amount) ->
        FinanceCategory(name, name, "cart", TransactionType.EXPENSE, "categoryGreen", BigDecimal(amount), "EUR")
    }

    private class MovableClock(var instant: Instant, private val zone: ZoneId) : Clock() {
        override fun instant(): Instant = instant
        override fun getZone(): ZoneId = zone
        override fun withZone(zone: ZoneId?): Clock = this
    }

    private class MemoryInsights : InsightRepository {
        val rows = mutableListOf<HealthScoreSnapshot>()
        var failWrites = false
        override suspend fun recentSnapshots(limit: Int) = rows.sortedByDescending { it.timestamp }.take(limit)
        override suspend fun saveSnapshot(snapshot: HealthScoreSnapshot) = snapshot.also { rows += it }
        override suspend fun saveSnapshotIfNeeded(snapshot: HealthScoreSnapshot, zone: ZoneId): Boolean {
            if (failWrites) error("disk full")
            val day = snapshot.timestamp.atZone(zone).toLocalDate()
            if (rows.any { it.timestamp.atZone(zone).toLocalDate() == day }) return false
            rows += snapshot
            return true
        }
        override suspend fun forecastCache(): DailyForecastCache? = null
        override suspend fun saveForecastCache(cache: DailyForecastCache) = Unit
        override suspend fun clearForecastCache() = Unit
    }

    private fun viewModel(clock: Clock, preferences: UserPreferencesRepository, insights: InsightRepository, categories: List<FinanceCategory>? = budgets) =
        InsightsViewModel(FakeTransactionRepository(fixture), FakeGoalRepository(), preferences, FakeCategoryRepository(categories), clock, zone, insights)

    @Test
    fun ac02_toggleSurvivesANewViewModel() = runTest(dispatcher) {
        val clock = MovableClock(at(9, 15), zone)
        val preferences = UserPreferencesRepository(FakePreferencesDataStore())
        val first = viewModel(clock, preferences, MemoryInsights())
        backgroundScope.launch(dispatcher) { first.uiState.collect {} }
        advanceUntilIdle()
        assertEquals(67, first.uiState.value.health?.score)

        first.setIgnoreSubscriptions(true)
        advanceUntilIdle()
        assertEquals(57, first.uiState.value.health?.score)

        // A fresh model over the same stored preferences: what the app sees after a restart.
        val second = viewModel(clock, preferences, MemoryInsights())
        backgroundScope.launch(dispatcher) { second.uiState.collect {} }
        advanceUntilIdle()
        val state = second.uiState.value
        assertTrue(state.ignoreSubscriptions)
        assertEquals(57, state.health?.score)
        assertEquals(listOf(HealthComponentKind.SAVINGS, HealthComponentKind.STABILITY, HealthComponentKind.BUDGET), state.health?.components?.map { it.kind })
    }

    @Test
    fun ac04_oneSnapshotPerDayAndTheHistoryReReads() = runTest(dispatcher) {
        val clock = MovableClock(at(9, 15), zone)
        val insights = MemoryInsights()
        val vm = viewModel(clock, UserPreferencesRepository(FakePreferencesDataStore()), insights)
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()
        assertEquals(1, insights.rows.size)
        val saved = insights.rows.single()
        assertEquals(listOf(67, 20, 12, 12, 23), listOf(saved.score, saved.savingsScore, saved.stabilityScore, saved.adherenceScore, saved.subscriptionScore))
        assertEquals(1, vm.uiState.value.snapshots.size)

        vm.refreshNow()
        vm.selectType(com.rizzog99.personalfinancetracker.domain.insights.ExplorerType.INCOME)
        advanceUntilIdle()
        assertEquals("no second snapshot the same day", 1, insights.rows.size)

        // A foreground into the next cycle, with no data change: a new day, a new reading.
        clock.instant = at(10, 1, 9)
        vm.refreshNow()
        advanceUntilIdle()
        assertEquals(2, insights.rows.size)
        assertEquals(2, vm.uiState.value.snapshots.size)
    }

    @Test
    fun ac04_ignoringSavesZeroForSubscriptions() = runTest(dispatcher) {
        val preferences = UserPreferencesRepository(FakePreferencesDataStore()).also { it.setHealthScoreIgnoreSubscriptions(true) }
        val insights = MemoryInsights()
        val vm = viewModel(MovableClock(at(9, 15), zone), preferences, insights)
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()
        val saved = insights.rows.single()
        assertEquals(listOf(57, 27, 15, 15, 0), listOf(saved.score, saved.savingsScore, saved.stabilityScore, saved.adherenceScore, saved.subscriptionScore))
    }

    @Test
    fun ac04_nothingIsSavedFromAFailedReadAndAFailedWriteBreaksNothing() = runTest(dispatcher) {
        val insights = MemoryInsights()
        val failedRead = viewModel(MovableClock(at(9, 15), zone), UserPreferencesRepository(FakePreferencesDataStore()), insights, categories = null)
        backgroundScope.launch(dispatcher) { failedRead.uiState.collect {} }
        advanceUntilIdle()
        assertTrue(failedRead.uiState.value.isError)
        assertTrue(insights.rows.isEmpty())

        insights.failWrites = true
        val failedWrite = viewModel(MovableClock(at(9, 15), zone), UserPreferencesRepository(FakePreferencesDataStore()), insights)
        backgroundScope.launch(dispatcher) { failedWrite.uiState.collect {} }
        advanceUntilIdle()
        assertFalse(failedWrite.uiState.value.isError)
        assertEquals(67, failedWrite.uiState.value.health?.score)
        assertTrue(insights.rows.isEmpty())
    }

    @Test
    fun ac01_noActivityMeansNoScore() = runTest(dispatcher) {
        val vm = InsightsViewModel(
            FakeTransactionRepository(emptyList()), FakeGoalRepository(), UserPreferencesRepository(FakePreferencesDataStore()),
            FakeCategoryRepository(emptyList()), MovableClock(at(9, 15), zone), zone, MemoryInsights(),
        )
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()
        assertFalse(vm.uiState.value.isLoading)
        assertNull(vm.uiState.value.health)
    }
}
