package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.time.Instant
import java.time.LocalTime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

internal val Context.userPreferencesDataStore by preferencesDataStore(name = "user_preferences")

class UserPreferencesRepository(private val dataStore: DataStore<Preferences>) {

    /** Production path: the one process-wide store named `user_preferences`. */
    constructor(context: Context) : this(context.userPreferencesDataStore)

    /**
     * Every key this repository can write. Declared as a list rather than only as properties so a
     * test can assert the whole preference surface, and fail when a key is added without being
     * classified as secret or non-secret (parity `M1-DATA-PREFS`, AC-06).
     */
    internal object Keys {
        val payCycleStartDay = intPreferencesKey("pay_cycle_start_day")
        val baseCurrency = stringPreferencesKey("base_currency")
        val themeMode = stringPreferencesKey("theme_mode")
        val hideBalance = booleanPreferencesKey("hide_balance")
        val lastBackupAt = longPreferencesKey("last_backup_at")
        val biometricEnabled = booleanPreferencesKey("biometric_enabled")
        val pinHash = stringPreferencesKey("pin_hash")
        val pinSalt = stringPreferencesKey("pin_salt")
        val dailyReminderEnabled = booleanPreferencesKey("daily_reminder_enabled")
        val dailyReminderHour = intPreferencesKey("daily_reminder_hour")
        val dailyReminderMinute = intPreferencesKey("daily_reminder_minute")
        val pulsePromptDismissed = booleanPreferencesKey("pulse_prompt_dismissed")
        val userFullName = stringPreferencesKey("user_full_name")
        val healthScoreIgnoreSubscriptions = booleanPreferencesKey("health_score_ignore_subscriptions")

        val all: List<Preferences.Key<*>> = listOf(
            payCycleStartDay,
            baseCurrency,
            themeMode,
            hideBalance,
            lastBackupAt,
            biometricEnabled,
            pinHash,
            pinSalt,
            dailyReminderEnabled,
            dailyReminderHour,
            dailyReminderMinute,
            pulsePromptDismissed,
            userFullName,
            healthScoreIgnoreSubscriptions,
        )
    }

    val payCycleStartDay: Flow<Int> = dataStore.data.map {
        (it[Keys.payCycleStartDay] ?: 1).coerceIn(1, 28)
    }

    val baseCurrency: Flow<String> = dataStore.data.map {
        it[Keys.baseCurrency] ?: "EUR"
    }

    val themeMode: Flow<ThemeMode> = dataStore.data.map {
        it[Keys.themeMode]?.let { name -> runCatching { ThemeMode.valueOf(name) }.getOrNull() } ?: ThemeMode.SYSTEM
    }

    val hideBalance: Flow<Boolean> = dataStore.data.map {
        it[Keys.hideBalance] ?: false
    }

    val lastBackupAt: Flow<Instant?> = dataStore.data.map {
        it[Keys.lastBackupAt]?.let(Instant::ofEpochMilli)
    }

    val biometricEnabled: Flow<Boolean> = dataStore.data.map {
        it[Keys.biometricEnabled] ?: false
    }

    /** Null when no PIN has been set — the app is unlocked without a gate. */
    val pinHash: Flow<String?> = dataStore.data.map { it[Keys.pinHash] }
    val pinSalt: Flow<String?> = dataStore.data.map { it[Keys.pinSalt] }

    val dailyReminderEnabled: Flow<Boolean> = dataStore.data.map {
        it[Keys.dailyReminderEnabled] ?: false
    }

    /**
     * When the daily reminder fires, as local wall-clock time. Stored as two ints rather than an
     * instant or a formatted string so it never drifts with the timezone: 21:00 means 21:00 after
     * the user flies somewhere else. `21:00` is the frozen-iOS default (#129 AC-01) and lives only
     * here, so nothing downstream can re-declare it.
     */
    val dailyReminderTime: Flow<LocalTime> = dataStore.data.map {
        LocalTime.of(
            (it[Keys.dailyReminderHour] ?: DEFAULT_REMINDER_HOUR).coerceIn(0, 23),
            (it[Keys.dailyReminderMinute] ?: DEFAULT_REMINDER_MINUTE).coerceIn(0, 59),
        )
    }

    val pulsePromptDismissed: Flow<Boolean> = dataStore.data.map {
        it[Keys.pulsePromptDismissed] ?: false
    }

    /**
     * The profile name, empty when never set — frozen iOS reads `user_full_name` as
     * `string(forKey:) ?? ""`, so an absent key is the default rather than a stored blank.
     */
    val userFullName: Flow<String> = dataStore.data.map {
        it[Keys.userFullName] ?: ""
    }

    /** Health-score preference; frozen iOS default is `bool(forKey:)`, i.e. false. */
    val healthScoreIgnoreSubscriptions: Flow<Boolean> = dataStore.data.map {
        it[Keys.healthScoreIgnoreSubscriptions] ?: false
    }

    suspend fun setLastBackupAt(instant: Instant) {
        dataStore.edit { it[Keys.lastBackupAt] = instant.toEpochMilli() }
    }

    suspend fun setBiometricEnabled(enabled: Boolean) {
        dataStore.edit { it[Keys.biometricEnabled] = enabled }
    }

    suspend fun setPin(hash: String, salt: String) {
        dataStore.edit {
            it[Keys.pinHash] = hash
            it[Keys.pinSalt] = salt
        }
    }

    suspend fun clearPin() {
        dataStore.edit {
            it.remove(Keys.pinHash)
            it.remove(Keys.pinSalt)
            it[Keys.biometricEnabled] = false
        }
    }

    suspend fun setPayCycleStartDay(day: Int) {
        dataStore.edit { it[Keys.payCycleStartDay] = day.coerceIn(1, 28) }
    }

    suspend fun setBaseCurrency(currencyCode: String) {
        dataStore.edit { it[Keys.baseCurrency] = currencyCode }
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        dataStore.edit { it[Keys.themeMode] = mode.name }
    }

    suspend fun setHideBalance(hidden: Boolean) {
        dataStore.edit { it[Keys.hideBalance] = hidden }
    }

    suspend fun setDailyReminderEnabled(enabled: Boolean) {
        dataStore.edit { it[Keys.dailyReminderEnabled] = enabled }
    }

    /** Normalized on write as well as on read, so a value from another build cannot resurrect. */
    suspend fun setDailyReminderTime(time: LocalTime) {
        dataStore.edit {
            it[Keys.dailyReminderHour] = time.hour.coerceIn(0, 23)
            it[Keys.dailyReminderMinute] = time.minute.coerceIn(0, 59)
        }
    }

    suspend fun setPulsePromptDismissed(dismissed: Boolean) {
        dataStore.edit { it[Keys.pulsePromptDismissed] = dismissed }
    }

    /**
     * Stores the trimmed name. A name that is blank once trimmed clears the key instead of storing
     * whitespace, so the default path and "the user cleared their name" stay the same state.
     *
     * Frozen iOS is inconsistent here: onboarding trims and skips the write when blank, while the
     * profile screen writes the raw string including `""`. Normalizing on write covers both without
     * ever persisting a whitespace-only placeholder.
     */
    suspend fun setUserFullName(name: String) {
        val trimmed = name.trim()
        dataStore.edit {
            if (trimmed.isEmpty()) it.remove(Keys.userFullName) else it[Keys.userFullName] = trimmed
        }
    }

    suspend fun setHealthScoreIgnoreSubscriptions(ignore: Boolean) {
        dataStore.edit { it[Keys.healthScoreIgnoreSubscriptions] = ignore }
    }

    private companion object {
        const val DEFAULT_REMINDER_HOUR = 21
        const val DEFAULT_REMINDER_MINUTE = 0
    }
}
