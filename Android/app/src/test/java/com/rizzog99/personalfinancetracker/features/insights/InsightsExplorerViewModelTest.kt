package com.rizzog99.personalfinancetracker.features.insights

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerGranularity
import com.rizzog99.personalfinancetracker.domain.insights.ExplorerType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.states.FakeCategoryRepository
import com.rizzog99.personalfinancetracker.features.states.FakeGoalRepository
import com.rizzog99.personalfinancetracker.features.states.FakePreferencesDataStore
import com.rizzog99.personalfinancetracker.features.states.FakeTransactionRepository
import com.rizzog99.personalfinancetracker.features.states.INJECTED_TECHNICAL_MESSAGE
import com.rizzog99.personalfinancetracker.features.states.transaction
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** #303 AC-07: the explorer's selection survives every refresh; a failed read is an error state. */
@OptIn(ExperimentalCoroutinesApi::class)
class InsightsExplorerViewModelTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val zone = ZoneId.of("Europe/Rome")
    private val clock = Clock.fixed(LocalDateTime.of(2026, 9, 10, 12, 0).atZone(zone).toInstant(), zone)

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun on(month: Int, day: Int): Instant = LocalDateTime.of(2026, month, day, 12, 0).atZone(zone).toInstant()

    /** A store whose rows can change, as Room's flow does after a write. */
    private class LiveTransactions(initial: List<FinanceTransaction>) :
        TransactionRepository by FakeTransactionRepository(initial) {
        val rows = MutableStateFlow(initial)
        override fun observeAll(): Flow<List<FinanceTransaction>> = rows
    }

    @Test
    fun ac07_periodSurvivesDataAndPayCycleChanges() = runTest(dispatcher) {
        val store = LiveTransactions(
            listOf(
                transaction("a", "-100.00", categoryLabel = "Food", timestamp = on(8, 5)),
                transaction("b", "-60.00", categoryLabel = "Food", timestamp = on(9, 3)),
            ),
        )
        val preferences = UserPreferencesRepository(FakePreferencesDataStore())
        val vm = InsightsViewModel(store, FakeGoalRepository(), preferences, FakeCategoryRepository(emptyList()), clock, zone)
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()
        assertEquals(LocalDate.of(2026, 9, 1), vm.uiState.value.explorerPeriod!!.start.atZone(zone).toLocalDate())

        vm.previousPeriod()
        vm.selectType(ExplorerType.EXPENSES)
        advanceUntilIdle()
        val august = vm.uiState.value.explorerPeriod!!
        assertEquals(LocalDate.of(2026, 8, 1), august.start.atZone(zone).toLocalDate())
        assertFalse("‹ stops at the first transaction's period", vm.uiState.value.canGoPrevious)
        assertTrue(vm.uiState.value.canGoNext)

        store.rows.update { it + transaction("c", "-40.00", categoryLabel = "Food", timestamp = on(8, 20)) }
        preferences.setPayCycleStartDay(15)
        advanceUntilIdle()

        val state = vm.uiState.value
        assertEquals(august, state.explorerPeriod)
        assertEquals(0, BigDecimal("140.00").compareTo(state.explorer.total))

        vm.selectGranularity(ExplorerGranularity.YEAR)
        advanceUntilIdle()
        assertEquals(LocalDate.of(2026, 1, 1), vm.uiState.value.explorerPeriod!!.start.atZone(zone).toLocalDate())
    }

    @Test
    fun ac07_readFailureIsAnErrorState() = runTest(dispatcher) {
        val vm = InsightsViewModel(
            FakeTransactionRepository(listOf(transaction("a", "-1.00"))),
            FakeGoalRepository(),
            UserPreferencesRepository(FakePreferencesDataStore()),
            FakeCategoryRepository(categories = null),
            clock,
            zone,
        )
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()

        assertTrue(vm.uiState.value.isError)
        assertFalse(vm.uiState.value.toString().contains(INJECTED_TECHNICAL_MESSAGE))
    }
}
