package com.rizzog99.personalfinancetracker.features.insights

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.features.states.FakeCategoryRepository
import com.rizzog99.personalfinancetracker.features.states.FakeGoalRepository
import com.rizzog99.personalfinancetracker.features.states.FakePreferencesDataStore
import com.rizzog99.personalfinancetracker.features.states.FakeTransactionRepository
import com.rizzog99.personalfinancetracker.features.states.transaction
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
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

/**
 * #300 AC-02: a transfer counts toward its goal's saved amount and stays out of the category
 * breakdown (iOS `InsightsViewModel.swift:158`, `:350-354` at b649dff).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class InsightsGoalTransferTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val clock = Clock.fixed(Instant.parse("2026-09-20T12:00:00Z"), ZoneOffset.UTC)

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun ac02_transfersCountAsSavedNotSpent() = runTest(dispatcher) {
        val emergencyFund = FinanceGoal("goal-ef", "Emergency fund", BigDecimal("5000"), null, "categoryIndigo", "star.fill", Instant.EPOCH)
        val vm = InsightsViewModel(
            transactionRepository = FakeTransactionRepository(
                listOf(
                    transaction("t", "-80.00", categoryLabel = "→ Emergency fund").copy(goalId = "goal-ef"),
                    transaction("f", "-30.00", categoryLabel = "Food"),
                ),
            ),
            goalRepository = FakeGoalRepository(listOf(emergencyFund)),
            preferencesRepository = UserPreferencesRepository(FakePreferencesDataStore()),
            categoryRepository = FakeCategoryRepository(emptyList()),
            clock = clock,
            zoneId = ZoneOffset.UTC,
        )
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()

        val state = vm.uiState.value
        assertEquals(0, BigDecimal("80.00").compareTo(state.goals.single().currentAmount))
        assertEquals(listOf("Food"), state.explorer.trends.map { it.label })
    }
}
