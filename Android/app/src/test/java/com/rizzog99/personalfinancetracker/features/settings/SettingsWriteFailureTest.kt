package com.rizzog99.personalfinancetracker.features.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
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
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** #298 review r1: a failed buffer write stays inside the ViewModel (#133) and the stored value stays shown. */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class SettingsWriteFailureTest {
    private val dispatcher = UnconfinedTestDispatcher()

    private class ReadOnlyStore : DataStore<Preferences> {
        override val data: Flow<Preferences> = flowOf(emptyPreferences())
        override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
            throw IOException("disk full")
    }

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun aFailedBufferWriteDoesNotEscapeAndKeepsTheStoredValue() = runTest(dispatcher) {
        val viewModel = SettingsViewModel(UserPreferencesRepository(ReadOnlyStore()))
        backgroundScope.launch(dispatcher) { viewModel.uiState.collect {} }
        advanceUntilIdle()

        // runTest fails the test on any exception that escapes into the scope's handler.
        viewModel.setBufferPercent(0)
        viewModel.setPayCycleStartDay(15)
        advanceUntilIdle()

        assertEquals(5, viewModel.uiState.value.bufferPercent)
        assertEquals(1, viewModel.uiState.value.payCycleStartDay)
    }
}
