package com.rizzog99.personalfinancetracker.features.insights

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.features.states.FakeCategoryRepository
import com.rizzog99.personalfinancetracker.features.states.FakeGoalRepository
import com.rizzog99.personalfinancetracker.features.states.FakePreferencesDataStore
import com.rizzog99.personalfinancetracker.features.states.FakeTransactionRepository
import com.rizzog99.personalfinancetracker.features.states.category
import com.rizzog99.personalfinancetracker.features.states.transaction
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** #291 AC-03: Insights category rows carry their own category, so they draw its icon and colour. */
@OptIn(ExperimentalCoroutinesApi::class)
class InsightsCategoryStyleTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val clock = Clock.fixed(Instant.parse("2026-09-20T12:00:00Z"), ZoneOffset.UTC)

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun viewModel(categories: FakeCategoryRepository) = InsightsViewModel(
        transactionRepository = FakeTransactionRepository(
            listOf(
                transaction("p", "-40.00", categoryLabel = "Palestra").copy(categoryId = "palestra"),
                transaction("x", "-5.00", categoryLabel = "Loose"),
            ),
        ),
        goalRepository = FakeGoalRepository(),
        preferencesRepository = UserPreferencesRepository(FakePreferencesDataStore()),
        categoryRepository = categories,
        clock = clock,
        zoneId = ZoneOffset.UTC,
    )

    @Test
    fun ac03_rowsCarryTheirOwnCategory() = runTest(dispatcher) {
        val palestra = category("palestra", "Palestra").copy(iconToken = "dumbbell", colorToken = "categoryPink")
        val vm = viewModel(FakeCategoryRepository(listOf(palestra)))
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()

        val rows = vm.uiState.value.categorySpending.associateBy { it.label }
        assertEquals(palestra, rows.getValue("Palestra").category)
        assertNull(rows.getValue("Loose").category)
    }

    @Test
    fun ac03_aCategoryReadFailureIsAnError() = runTest(dispatcher) {
        val vm = viewModel(FakeCategoryRepository(categories = null))
        backgroundScope.launch(dispatcher) { vm.uiState.collect {} }
        advanceUntilIdle()

        assertTrue(vm.uiState.value.isError)
    }
}
