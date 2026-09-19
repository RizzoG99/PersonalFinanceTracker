package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.backup.BackupRepository
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Parity `M1-DATA-PREFS` (#118), AC-01 to AC-06.
 *
 * Every test drives the production [UserPreferencesRepository] against a real file-backed
 * Preferences DataStore created the same way the production `preferencesDataStore` delegate creates
 * it. "Restart" means the store's scope is cancelled and joined — releasing DataStore's per-file
 * lock — and a brand new store and repository are built over the same file, which is the closest a
 * JVM test gets to the process actually restarting.
 */
@RunWith(RobolectricTestRunner::class)
class UserPreferencesPersistenceTest {

    private lateinit var context: Context
    private lateinit var file: File
    private var session: StoreSession? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        file = context.preferencesDataStoreFile("m1_data_prefs_ac")
        file.delete()
    }

    @After
    fun tearDown() = runBlocking {
        session?.close()
        file.delete()
        Unit
    }

    @Test
    fun `AC-01 a clean store exposes every documented default and writes no placeholder`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())

        assertEquals(1, repository.payCycleStartDay.first())
        assertEquals("EUR", repository.baseCurrency.first())
        assertEquals(ThemeMode.SYSTEM, repository.themeMode.first())
        assertEquals(false, repository.hideBalance.first())
        assertNull(repository.lastBackupAt.first())
        assertEquals(false, repository.biometricEnabled.first())
        assertNull(repository.pinHash.first())
        assertNull(repository.pinSalt.first())
        assertEquals(false, repository.dailyReminderEnabled.first())
        assertEquals(false, repository.pulsePromptDismissed.first())
        assertEquals("", repository.userFullName.first())
        assertEquals(false, repository.healthScoreIgnoreSubscriptions.first())

        // The distinction AC-01 asks for: these are computed defaults over an absent key, not
        // values someone wrote at first launch. Reading must not have created the file either.
        assertEquals(emptyMap<Preferences.Key<*>, Any>(), requireNotNull(session).store.data.first().asMap())
        assertEquals(false, file.exists())
    }

    @Test
    fun `AC-02 every included preference survives a full store restart at boundary values`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())

        repository.setPayCycleStartDay(28)
        repository.setBaseCurrency("CHF")
        repository.setThemeMode(ThemeMode.DARK)
        repository.setHideBalance(true)
        repository.setLastBackupAt(Instant.ofEpochMilli(-86_400_000))
        repository.setDailyReminderEnabled(true)
        repository.setPulsePromptDismissed(true)
        repository.setUserFullName("  Zoë  Van Der Berg-O'Neill 名前  ")
        repository.setHealthScoreIgnoreSubscriptions(true)

        val reopened = UserPreferencesRepository(restart())

        assertEquals(28, reopened.payCycleStartDay.first())
        assertEquals("CHF", reopened.baseCurrency.first())
        assertEquals(ThemeMode.DARK, reopened.themeMode.first())
        assertEquals(true, reopened.hideBalance.first())
        assertEquals(Instant.ofEpochMilli(-86_400_000), reopened.lastBackupAt.first())
        assertEquals(true, reopened.dailyReminderEnabled.first())
        assertEquals(true, reopened.pulsePromptDismissed.first())
        assertEquals("Zoë  Van Der Berg-O'Neill 名前", reopened.userFullName.first())
        assertEquals(true, reopened.healthScoreIgnoreSubscriptions.first())
    }

    @Test
    fun `AC-02 the lowest pay cycle day and epoch backup timestamp also survive a restart`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())

        repository.setPayCycleStartDay(1)
        repository.setLastBackupAt(Instant.EPOCH)
        repository.setThemeMode(ThemeMode.LIGHT)

        val reopened = UserPreferencesRepository(restart())

        assertEquals(1, reopened.payCycleStartDay.first())
        assertEquals(Instant.EPOCH, reopened.lastBackupAt.first())
        assertEquals(ThemeMode.LIGHT, reopened.themeMode.first())
    }

    @Test
    fun `AC-03 a blank or whitespace profile name clears the key instead of storing a placeholder`() = runBlocking {
        val store = openStore()
        val repository = UserPreferencesRepository(store)

        repository.setBaseCurrency("GBP")
        repository.setUserFullName("Ada Lovelace")
        assertEquals("Ada Lovelace", repository.userFullName.first())

        repository.setUserFullName("   \t \n ")

        assertEquals("", repository.userFullName.first())
        assertEquals(false, store.data.first().contains(UserPreferencesRepository.Keys.userFullName))
        // The rejected write must not disturb anything else.
        assertEquals("GBP", repository.baseCurrency.first())
    }

    @Test
    fun `AC-03 out of range pay cycle days normalize deterministically in both directions`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())

        repository.setPayCycleStartDay(0)
        assertEquals(1, repository.payCycleStartDay.first())
        repository.setPayCycleStartDay(-7)
        assertEquals(1, repository.payCycleStartDay.first())
        repository.setPayCycleStartDay(31)
        assertEquals(28, repository.payCycleStartDay.first())
        repository.setPayCycleStartDay(Int.MAX_VALUE)
        assertEquals(28, repository.payCycleStartDay.first())

        // Normalized on write, so a restart cannot resurrect the raw value.
        assertEquals(28, UserPreferencesRepository(restart()).payCycleStartDay.first())
    }

    @Test
    fun `AC-03 a pay cycle day stored as text is rejected loudly rather than read as a wrong number`() = runBlocking {
        val store = openStore()
        val repository = UserPreferencesRepository(store)
        repository.setBaseCurrency("PLN")

        // Only reachable if a future build retypes this key and the user downgrades. Frozen iOS
        // coerces (`integer(forKey:)` on a string yields 0, i.e. the default); DataStore's typed
        // keys raise instead. Pinned so the behavior is recorded, not discovered in the field.
        store.edit { it[stringPreferencesKey("pay_cycle_start_day")] = "seventeen" }

        assertThrows(ClassCastException::class.java) {
            runBlocking { repository.payCycleStartDay.first() }
        }
        // The malformed value is confined to its own key: everything else still reads.
        assertEquals("PLN", repository.baseCurrency.first())
        assertEquals(ThemeMode.SYSTEM, repository.themeMode.first())
        assertEquals("", repository.userFullName.first())

        // And a fresh write repairs the key without clearing the store.
        repository.setPayCycleStartDay(12)
        assertEquals(12, repository.payCycleStartDay.first())
        assertEquals("PLN", repository.baseCurrency.first())
    }

    @Test
    fun `AC-04 concurrent writes to independent preferences all commit and stay observable`() = runBlocking {
        val store = openStore()
        val repository = UserPreferencesRepository(store)
        val names = List(REPEATS) { "Writer $it" }

        val writers = buildList<suspend () -> Unit> {
            add { repository.setPayCycleStartDay(17) }
            add { repository.setBaseCurrency("SEK") }
            add { repository.setThemeMode(ThemeMode.DARK) }
            add { repository.setHideBalance(true) }
            add { repository.setLastBackupAt(Instant.ofEpochMilli(1_700_000_000_000)) }
            add { repository.setDailyReminderEnabled(true) }
            add { repository.setPulsePromptDismissed(true) }
            add { repository.setHealthScoreIgnoreSubscriptions(true) }
            add { repository.setUserFullName("Grace Hopper") }
            // Same-key contenders: DataStore's contract is serialized last-writer-wins, so the
            // winner must be one of the committed values, never a torn or absent one.
            names.forEach { name -> add { repository.setUserFullName(name) } }
        }

        writers.map { write -> async(Dispatchers.Default) { write() } }.awaitAll()

        assertEquals(17, repository.payCycleStartDay.first())
        assertEquals("SEK", repository.baseCurrency.first())
        assertEquals(ThemeMode.DARK, repository.themeMode.first())
        assertEquals(true, repository.hideBalance.first())
        assertEquals(Instant.ofEpochMilli(1_700_000_000_000), repository.lastBackupAt.first())
        assertEquals(true, repository.dailyReminderEnabled.first())
        assertEquals(true, repository.pulsePromptDismissed.first())
        assertEquals(true, repository.healthScoreIgnoreSubscriptions.first())
        assertTrue(repository.userFullName.first() in names + "Grace Hopper")

        // All of it is on disk, not just in a cached snapshot.
        val reopened = UserPreferencesRepository(restart())
        assertEquals(17, reopened.payCycleStartDay.first())
        assertEquals("SEK", reopened.baseCurrency.first())
        assertEquals(ThemeMode.DARK, reopened.themeMode.first())
        assertEquals(true, reopened.hideBalance.first())
        assertEquals(true, reopened.healthScoreIgnoreSubscriptions.first())
    }

    @Test
    fun `AC-05 an unsupported theme name falls back to the default without touching other preferences`() = runBlocking {
        val store = openStore()
        val repository = UserPreferencesRepository(store)
        repository.setBaseCurrency("NOK")
        repository.setUserFullName("Katherine Johnson")
        repository.setPayCycleStartDay(9)

        // A build that knew a theme this one does not, e.g. after a downgrade.
        store.edit { it[UserPreferencesRepository.Keys.themeMode] = "HIGH_CONTRAST_DARK" }

        assertEquals(ThemeMode.SYSTEM, repository.themeMode.first())
        assertEquals("NOK", repository.baseCurrency.first())
        assertEquals("Katherine Johnson", repository.userFullName.first())
        assertEquals(9, repository.payCycleStartDay.first())
        // Reading must not repair the store by clearing it — the unknown value is still there,
        // so an upgrade that understands it again finds it intact.
        assertEquals("HIGH_CONTRAST_DARK", store.data.first()[UserPreferencesRepository.Keys.themeMode])

        val reopened = UserPreferencesRepository(restart())
        assertEquals(ThemeMode.SYSTEM, reopened.themeMode.first())
        assertEquals("NOK", reopened.baseCurrency.first())
        assertEquals("Katherine Johnson", reopened.userFullName.first())
    }

    @Test
    fun `AC-05 keys from a newer build survive a restart and do not disturb known preferences`() = runBlocking {
        val store = openStore()
        val repository = UserPreferencesRepository(store)
        val unknownString = stringPreferencesKey("weekly_digest_channel")
        val unknownBoolean = booleanPreferencesKey("round_up_savings_enabled")

        store.edit {
            it[unknownString] = "email"
            it[unknownBoolean] = true
        }
        repository.setThemeMode(ThemeMode.LIGHT)
        repository.setUserFullName("Mary Jackson")

        val restarted = restart()
        val reopened = UserPreferencesRepository(restarted)

        assertEquals(ThemeMode.LIGHT, reopened.themeMode.first())
        assertEquals("Mary Jackson", reopened.userFullName.first())
        // Writing through this build must not drop fields it does not know about.
        assertEquals("email", restarted.data.first()[unknownString])
        assertEquals(true, restarted.data.first()[unknownBoolean])
    }

    @Test
    fun `AC-06 the preference key inventory is exactly the documented surface`() {
        val declared = UserPreferencesRepository.Keys.all.map { it.name } +
            ImportProfileRepository.Keys.all.map { it.name }

        assertEquals(DOCUMENTED_KEYS, declared.toSet())
        assertEquals(DOCUMENTED_KEYS.size, declared.size)

        // Tripwire: a key declared on either Keys object but left out of `all` — the list the
        // inventory above is checked against — fails here rather than slipping in unclassified.
        assertEquals(
            UserPreferencesRepository.Keys.all.toSet(),
            declaredKeysByReflection(UserPreferencesRepository.Keys),
        )
        assertEquals(
            ImportProfileRepository.Keys.all.toSet(),
            declaredKeysByReflection(ImportProfileRepository.Keys),
        )
    }

    @Test
    fun `AC-06 no non-secret preference name collides with device-only secret material`() {
        val nonSecret = DOCUMENTED_KEYS - SECURITY_KEYS
        val secretish = listOf("pin", "hash", "salt", "token", "key", "credential", "secret", "password", "passphrase", "drive")

        nonSecret.forEach { name ->
            secretish.forEach { needle ->
                assertTrue(
                    "Preference '$name' looks like secret material; secret storage belongs to #80, not this store",
                    !name.contains(needle),
                )
            }
        }
        // The two keys this store does hold that iOS keeps in the Keychain instead. Pinned here so
        // the divergence stays visible and cannot quietly grow. See #118 D-02 / #80.
        assertEquals(setOf("pin_hash", "pin_salt"), SECURITY_KEYS - "biometric_enabled")
    }

    @Test
    fun `AC-06 the portable backup archive carries no preference or secret material`() = runBlocking {
        val database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        val transactions = RoomTransactionRepository(database)
        val categories = RoomCategoryRepository(database)
        val goals = RoomGoalRepository(database)
        categories.add(
            NewCategory(
                name = "Groceries",
                iconToken = "cart",
                type = TransactionType.EXPENSE,
                colorToken = "categoryTeal",
                monthlyBudget = null,
                currencyCode = "EUR",
            ),
        )

        // A store holding every preference, secret keys included, is live while the export runs.
        val repository = UserPreferencesRepository(openStore())
        repository.setPin("a-pin-hash", "a-pin-salt")
        repository.setBiometricEnabled(true)
        repository.setUserFullName("Annie Easley")

        val archive = ByteArrayOutputStream()
        BackupRepository(database, transactions, categories, goals).export(archive)
        database.close()

        val json = JSONObject(archive.toString(Charsets.UTF_8.name()))
        assertEquals(
            setOf("version", "exportedAt", "categories", "transactions", "goals"),
            json.keys().asSequence().toSet(),
        )
        val text = archive.toString(Charsets.UTF_8.name())
        (DOCUMENTED_KEYS + listOf("a-pin-hash", "a-pin-salt", "Annie Easley")).forEach { needle ->
            assertTrue("Backup archive leaked '$needle'", !text.contains(needle))
        }
    }

    private fun openStore(): DataStore<Preferences> = StoreSession(file).also { session = it }.store

    /** Cancels the store's scope, waits for the file lock to be released, and rebuilds over it. */
    private suspend fun restart(): DataStore<Preferences> {
        requireNotNull(session).close()
        return openStore()
    }

    private fun declaredKeysByReflection(keys: Any): Set<Preferences.Key<*>> =
        keys.javaClass.declaredFields
            .onEach { it.isAccessible = true }
            .mapNotNull { it.get(keys) as? Preferences.Key<*> }
            .toSet()

    private class StoreSession(file: File) {
        private val job = SupervisorJob()
        private val scope = CoroutineScope(Dispatchers.IO + job)
        val store: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file }

        suspend fun close() = job.cancelAndJoin()
    }

    private companion object {
        const val REPEATS = 24

        /**
         * The complete audited preference surface. Adding a key without adding it here is a test
         * failure on purpose — it forces the new key to be classified as non-secret (belongs here)
         * or as device-only secret material (belongs in #80's secure storage, not this store).
         */
        val DOCUMENTED_KEYS = setOf(
            "pay_cycle_start_day",
            "base_currency",
            "theme_mode",
            "hide_balance",
            "last_backup_at",
            "biometric_enabled",
            "pin_hash",
            "pin_salt",
            "daily_reminder_enabled",
            "pulse_prompt_dismissed",
            "user_full_name",
            "health_score_ignore_subscriptions",
            "import_profiles_v1",
        )

        val SECURITY_KEYS = setOf("pin_hash", "pin_salt", "biometric_enabled")
    }
}
