package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.IOException
import java.time.Instant
import java.time.LocalTime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

internal val Context.userPreferencesDataStore by preferencesDataStore(name = "user_preferences")

class UserPreferencesRepository(
    private val dataStore: DataStore<Preferences>,
    private val onUnreadable: () -> Unit = {},
) {

    /** Production path: the one process-wide store named `user_preferences`. */
    constructor(context: Context, onUnreadable: () -> Unit = {}) :
        this(context.userPreferencesDataStore, onUnreadable)

    /**
     * The single read source behind every preference below (#131).
     *
     * An unparseable `user_preferences.preferences_pb` raises `CorruptionException` — an
     * `IOException` — on `dataStore.data`. Left uncaught it killed the process: measured on
     * `emulator-5554` before this catch existed, a launch died with
     * `FATAL EXCEPTION: DefaultDispatcher-worker-8 / CorruptionException: Unable to parse
     * preferences proto`, on every launch, with no way back into the app.
     *
     * So the failure is reported once, here, and the flows stay total by falling back to empty
     * preferences. The defaults are never *shown* as if they were the user's — [onUnreadable]
     * puts the app into its recovery state — they only keep collectors alive while that happens.
     *
     * What this cannot catch, stated rather than papered over: a damaged file whose bytes still
     * *parse* as a protobuf. It yields an empty preference map and is then indistinguishable from
     * a store that was never written — no exception exists to observe. Injecting 4 KB of
     * `/dev/urandom` hit exactly that case during the #109 audit and looked like a silent reset.
     * Detecting it would need a checksum or version marker written alongside the preferences,
     * which is a storage-format change and belongs with #118, not here.
     *
     * No `ReplaceFileCorruptionHandler` is installed on purpose: that handler's job is to
     * overwrite the damaged file, which is the destructive fallback this app refuses. Nothing here
     * writes, so the user's file survives whatever went wrong with it.
     */
    private val readable: Flow<Preferences> = dataStore.data.catch { cause ->
        if (cause !is IOException) throw cause
        onUnreadable()
        emit(emptyPreferences())
    }

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
            dailyReminderEnabled,
            dailyReminderHour,
            dailyReminderMinute,
            pulsePromptDismissed,
            userFullName,
            healthScoreIgnoreSubscriptions,
        )
    }

    val payCycleStartDay: Flow<Int> = readable.map {
        (it[Keys.payCycleStartDay] ?: 1).coerceIn(1, 28)
    }

    val baseCurrency: Flow<String> = readable.map {
        it[Keys.baseCurrency] ?: "EUR"
    }

    val themeMode: Flow<ThemeMode> = readable.map {
        it[Keys.themeMode]?.let { name -> runCatching { ThemeMode.valueOf(name) }.getOrNull() } ?: ThemeMode.SYSTEM
    }

    val hideBalance: Flow<Boolean> = readable.map {
        it[Keys.hideBalance] ?: false
    }

    val lastBackupAt: Flow<Instant?> = readable.map {
        it[Keys.lastBackupAt]?.let(Instant::ofEpochMilli)
    }

    val biometricEnabled: Flow<Boolean> = readable.map {
        it[Keys.biometricEnabled] ?: false
    }

    val dailyReminderEnabled: Flow<Boolean> = readable.map {
        it[Keys.dailyReminderEnabled] ?: false
    }

    /**
     * When the daily reminder fires, as local wall-clock time. Stored as two ints rather than an
     * instant or a formatted string so it never drifts with the timezone: 21:00 means 21:00 after
     * the user flies somewhere else. `21:00` is the frozen-iOS default (#129 AC-01) and lives only
     * here, so nothing downstream can re-declare it.
     */
    val dailyReminderTime: Flow<LocalTime> = readable.map {
        LocalTime.of(
            (it[Keys.dailyReminderHour] ?: DEFAULT_REMINDER_HOUR).coerceIn(0, 23),
            (it[Keys.dailyReminderMinute] ?: DEFAULT_REMINDER_MINUTE).coerceIn(0, 59),
        )
    }

    val pulsePromptDismissed: Flow<Boolean> = readable.map {
        it[Keys.pulsePromptDismissed] ?: false
    }

    /**
     * The profile name, empty when never set — frozen iOS reads `user_full_name` as
     * `string(forKey:) ?? ""`, so an absent key is the default rather than a stored blank.
     */
    val userFullName: Flow<String> = readable.map {
        it[Keys.userFullName] ?: ""
    }

    /** Health-score preference; frozen iOS default is `bool(forKey:)`, i.e. false. */
    val healthScoreIgnoreSubscriptions: Flow<Boolean> = readable.map {
        it[Keys.healthScoreIgnoreSubscriptions] ?: false
    }

    suspend fun setLastBackupAt(instant: Instant) {
        dataStore.edit { it[Keys.lastBackupAt] = instant.toEpochMilli() }
    }

    suspend fun setBiometricEnabled(enabled: Boolean) {
        dataStore.edit { it[Keys.biometricEnabled] = enabled }
    }

    /**
     * The pre-#128 `pin_hash` / `pin_salt` pair, or null when neither key is present. Returned raw
     * — possibly half a pair, possibly blank — because deciding what an incomplete pair means
     * belongs to the migration, not here. This and [removeLegacyPinEntry] are the only code left
     * that touches these keys: they are migration input, never an authentication input, and they
     * are deliberately absent from [Keys] so the AC-06 inventory stays free of secret material.
     */
    internal suspend fun legacyPinEntry(): Pair<String?, String?>? {
        val preferences = dataStore.data.first()
        val hash = preferences[LegacyPinKeys.hash]
        val salt = preferences[LegacyPinKeys.salt]
        return if (hash == null && salt == null) null else hash to salt
    }

    internal suspend fun removeLegacyPinEntry() {
        dataStore.edit {
            it.remove(LegacyPinKeys.hash)
            it.remove(LegacyPinKeys.salt)
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

    /** Not part of [Keys]: these are legacy keys to be removed, not preferences this store owns. */
    internal object LegacyPinKeys {
        val hash = stringPreferencesKey("pin_hash")
        val salt = stringPreferencesKey("pin_salt")
    }

    private companion object {
        const val DEFAULT_REMINDER_HOUR = 21
        const val DEFAULT_REMINDER_MINUTE = 0
    }
}
