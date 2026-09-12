package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.userPreferencesDataStore by preferencesDataStore(name = "user_preferences")

class UserPreferencesRepository(private val context: Context) {
    private object Keys {
        val payCycleStartDay = intPreferencesKey("pay_cycle_start_day")
        val baseCurrency = stringPreferencesKey("base_currency")
        val themeMode = stringPreferencesKey("theme_mode")
        val hideBalance = booleanPreferencesKey("hide_balance")
    }

    val payCycleStartDay: Flow<Int> = context.userPreferencesDataStore.data.map {
        (it[Keys.payCycleStartDay] ?: 1).coerceIn(1, 28)
    }

    val baseCurrency: Flow<String> = context.userPreferencesDataStore.data.map {
        it[Keys.baseCurrency] ?: "EUR"
    }

    val themeMode: Flow<ThemeMode> = context.userPreferencesDataStore.data.map {
        it[Keys.themeMode]?.let { name -> runCatching { ThemeMode.valueOf(name) }.getOrNull() } ?: ThemeMode.SYSTEM
    }

    val hideBalance: Flow<Boolean> = context.userPreferencesDataStore.data.map {
        it[Keys.hideBalance] ?: false
    }

    suspend fun setPayCycleStartDay(day: Int) {
        context.userPreferencesDataStore.edit { it[Keys.payCycleStartDay] = day.coerceIn(1, 28) }
    }

    suspend fun setBaseCurrency(currencyCode: String) {
        context.userPreferencesDataStore.edit { it[Keys.baseCurrency] = currencyCode }
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.userPreferencesDataStore.edit { it[Keys.themeMode] = mode.name }
    }

    suspend fun setHideBalance(hidden: Boolean) {
        context.userPreferencesDataStore.edit { it[Keys.hideBalance] = hidden }
    }
}
