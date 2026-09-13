package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.userPreferencesDataStore by preferencesDataStore(name = "user_preferences")

class UserPreferencesRepository(private val context: Context) {
    private object Keys {
        val payCycleStartDay = intPreferencesKey("pay_cycle_start_day")
        val baseCurrency = stringPreferencesKey("base_currency")
        val themeMode = stringPreferencesKey("theme_mode")
        val hideBalance = booleanPreferencesKey("hide_balance")
        val lastBackupAt = longPreferencesKey("last_backup_at")
        val biometricEnabled = booleanPreferencesKey("biometric_enabled")
        val pinHash = stringPreferencesKey("pin_hash")
        val pinSalt = stringPreferencesKey("pin_salt")
        val dailyReminderEnabled = booleanPreferencesKey("daily_reminder_enabled")
        val pulsePromptDismissed = booleanPreferencesKey("pulse_prompt_dismissed")
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

    val lastBackupAt: Flow<Instant?> = context.userPreferencesDataStore.data.map {
        it[Keys.lastBackupAt]?.let(Instant::ofEpochMilli)
    }

    val biometricEnabled: Flow<Boolean> = context.userPreferencesDataStore.data.map {
        it[Keys.biometricEnabled] ?: false
    }

    /** Null when no PIN has been set — the app is unlocked without a gate. */
    val pinHash: Flow<String?> = context.userPreferencesDataStore.data.map { it[Keys.pinHash] }
    val pinSalt: Flow<String?> = context.userPreferencesDataStore.data.map { it[Keys.pinSalt] }

    val dailyReminderEnabled: Flow<Boolean> = context.userPreferencesDataStore.data.map {
        it[Keys.dailyReminderEnabled] ?: false
    }

    val pulsePromptDismissed: Flow<Boolean> = context.userPreferencesDataStore.data.map {
        it[Keys.pulsePromptDismissed] ?: false
    }

    suspend fun setLastBackupAt(instant: Instant) {
        context.userPreferencesDataStore.edit { it[Keys.lastBackupAt] = instant.toEpochMilli() }
    }

    suspend fun setBiometricEnabled(enabled: Boolean) {
        context.userPreferencesDataStore.edit { it[Keys.biometricEnabled] = enabled }
    }

    suspend fun setPin(hash: String, salt: String) {
        context.userPreferencesDataStore.edit {
            it[Keys.pinHash] = hash
            it[Keys.pinSalt] = salt
        }
    }

    suspend fun clearPin() {
        context.userPreferencesDataStore.edit {
            it.remove(Keys.pinHash)
            it.remove(Keys.pinSalt)
            it[Keys.biometricEnabled] = false
        }
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

    suspend fun setDailyReminderEnabled(enabled: Boolean) {
        context.userPreferencesDataStore.edit { it[Keys.dailyReminderEnabled] = enabled }
    }

    suspend fun setPulsePromptDismissed(dismissed: Boolean) {
        context.userPreferencesDataStore.edit { it[Keys.pulsePromptDismissed] = dismissed }
    }
}
