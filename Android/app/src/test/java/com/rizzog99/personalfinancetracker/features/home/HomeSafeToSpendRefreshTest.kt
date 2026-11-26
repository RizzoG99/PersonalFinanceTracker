package com.rizzog99.personalfinancetracker.features.home

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.domain.dashboard.SafeToSpendCalculator
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.states.FakeCategoryRepository
import com.rizzog99.personalfinancetracker.features.states.FakePreferencesDataStore
import com.rizzog99.personalfinancetracker.features.states.FakeTransactionRepository
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
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
import org.junit.Before
import org.junit.Test

/** #298 plan R4/R8: Home moves to a new day or cycle on [HomeViewModel.refresh], with no data change. */
@OptIn(ExperimentalCoroutinesApi::class)
class HomeSafeToSpendRefreshTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val zone = ZoneId.of("Europe/Rome")

    private class MutableClock(var instant: Instant, private val zone: ZoneId) : Clock() {
        override fun getZone(): ZoneId = zone
        override fun withZone(zone: ZoneId): Clock = MutableClock(instant, zone)
        override fun instant(): Instant = instant
    }

    private fun at(month: Int, day: Int, hour: Int = 12): Instant =
        LocalDateTime.of(2026, month, day, hour, 0).atZone(zone).toInstant()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun refreshMovesPerDayAndPaydayWithoutAnyDataChange() = runTest(dispatcher) {
        val preferences = UserPreferencesRepository(FakePreferencesDataStore())
        preferences.setPayCycleStartDay(27)
        val salary = FinanceTransaction(
            id = "salary", timestamp = at(9, 27), amount = BigDecimal("900"), note = "", categoryLabel = "",
            categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
        )
        val clock = MutableClock(at(10, 7), zone)
        val viewModel = HomeViewModel(
            transactionRepository = FakeTransactionRepository(listOf(salary)),
            preferencesRepository = preferences,
            categoryRepository = FakeCategoryRepository(),
            clock = clock,
            zoneId = zone,
        )
        backgroundScope.launch(dispatcher) { viewModel.uiState.collect {} }
        advanceUntilIdle()

        fun perDay(): BigDecimal? = viewModel.uiState.value.let { state ->
            SafeToSpendCalculator.perDay(state.safeToSpend!!.amount, state.today!!, state.safeToSpend!!.payday)
        }

        // 900 − 5 % = 855 over 20 days (7–26 Oct) → 42.75, rounded down.
        assertEquals(LocalDate.of(2026, 10, 27), viewModel.uiState.value.safeToSpend!!.payday)
        assertEquals(0, BigDecimal("42").compareTo(perDay()))

        clock.instant = at(10, 17)
        viewModel.refresh()
        advanceUntilIdle()
        assertEquals(LocalDate.of(2026, 10, 17), viewModel.uiState.value.today)
        assertEquals(0, BigDecimal("85").compareTo(perDay()))

        clock.instant = at(10, 27, 9)
        viewModel.refresh()
        advanceUntilIdle()
        assertEquals(LocalDate.of(2026, 11, 27), viewModel.uiState.value.safeToSpend!!.payday)

        // A data change after midnight, with no resume, is worked out for the new day too.
        clock.instant = at(10, 28, 9)
        preferences.setSafeToSpendBufferPercent(4)
        advanceUntilIdle()
        assertEquals(LocalDate.of(2026, 10, 28), viewModel.uiState.value.today)
        assertEquals(4, viewModel.uiState.value.bufferPercent)
    }
}
