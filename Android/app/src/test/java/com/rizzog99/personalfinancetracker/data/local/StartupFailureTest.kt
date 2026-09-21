package com.rizzog99.personalfinancetracker.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Parity `M1-APP-BOOT` (#109) `AC-06`, and the gaps it found: #130 (a corrupt database was deleted
 * and shown as an empty account) and #131 (a corrupt preferences file silently reset every
 * setting).
 *
 * The discriminating assertion in both halves is not "an exception was caught" — catching proves
 * nothing about recoverability. It is that the **bytes on disk are unchanged afterwards**, compared
 * against a copy taken before the damaged file was ever opened.
 *
 * Honest limitation, measured rather than assumed: a mutation check that dropped
 * [NonDestructiveOpenHelperFactory] was written here first and **did not fail** — Robolectric's
 * SQLite does not reproduce the platform's `DefaultDatabaseErrorHandler`, and left the corrupt
 * fixture at its original 106,496 bytes either way. So this class cannot prove the destruction it
 * prevents, only that the preserving path reports and preserves. The A/B that does prove it is
 * device-side, on `emulator-5554`: before the fix, one damaged page produced
 * `W SupportSQLite: deleting the database file` and a 4,096-byte empty schema; after it, the same
 * injection leaves the file intact. That device run is the mutation check for #130.
 */
@RunWith(RobolectricTestRunner::class)
class StartupFailureTest {

    private lateinit var context: Context
    private val databaseName = "m1-app-boot-corruption.db"
    private var session: StoreSession? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(databaseName)
    }

    @After
    fun tearDown() = runBlocking {
        session?.close()
        context.deleteDatabase(databaseName)
        Unit
    }

    @Test
    fun `AC-06 a corrupt database is reported and left byte-for-byte intact`() = runBlocking {
        val file = seedRealDatabase()
        corruptFirstPage(file)
        val damaged = file.readBytes()
        val reported = AtomicInteger()

        val database = Room
            .databaseBuilder(context, PersonalFinanceDatabase::class.java, databaseName)
            .addMigrations(*PersonalFinanceDatabase.MIGRATIONS)
            .openHelperFactory(NonDestructiveOpenHelperFactory(onCorruption = { reported.incrementAndGet() }))
            .allowMainThreadQueries()
            .build()
        val failure = runCatching { database.categoryDao().count() }.exceptionOrNull()
        database.close()

        assertNotNull("opening a corrupt database must not silently succeed", failure)
        assertTrue("the corruption must be reported so the UI can explain it", reported.get() >= 1)

        // The whole point of #130: the platform's default handler deleted this file.
        assertTrue("the database file must still exist", file.exists())
        assertEquals("the database file must not be truncated", damaged.size.toLong(), file.length())
        assertArrayEquals("not one byte of the user's database may change", damaged, file.readBytes())
    }

    @Test
    fun `AC-06 a healthy database is unaffected by the preserving helper`() = runBlocking {
        seedRealDatabase()
        val reported = AtomicInteger()

        val database = Room
            .databaseBuilder(context, PersonalFinanceDatabase::class.java, databaseName)
            .addMigrations(*PersonalFinanceDatabase.MIGRATIONS)
            .openHelperFactory(NonDestructiveOpenHelperFactory(onCorruption = { reported.incrementAndGet() }))
            .allowMainThreadQueries()
            .build()
        // Room's identity-hash check runs in the delegated onOpen; a callback that dropped it
        // would fail here rather than on the damaged path.
        val categories = RoomCategoryRepository(database).observeAll().first()
        database.close()

        assertEquals("no corruption may be reported for a healthy database", 0, reported.get())
        assertTrue("the seeded category must be readable", categories.any { it.name == "Boot fixture" })
    }

    @Test
    fun `AC-06 an unreadable preferences file is reported instead of reading as defaults`() = runBlocking {
        val file = context.preferencesDataStoreFile("m1_app_boot_prefs")
        file.parentFile?.mkdirs()
        file.writeBytes(ByteArray(512) { (it * 31 + 7).toByte() })
        val damaged = file.readBytes()
        val reported = AtomicInteger()

        val repository = UserPreferencesRepository(openStore(file)) { reported.incrementAndGet() }

        // Total, so nothing strands or crashes -- but the failure is now signalled, which is the
        // difference between "the user has no settings" and "the settings could not be read".
        assertEquals(ThemeMode.SYSTEM, repository.themeMode.first())
        assertEquals(1, repository.payCycleStartDay.first())
        assertTrue("the corruption must be reported", reported.get() >= 1)

        // #131 AC-02/AC-03: no ReplaceFileCorruptionHandler, and no default written back over it.
        assertTrue("the preferences file must still exist", file.exists())
        assertArrayEquals("the damaged preferences file must not be rewritten", damaged, file.readBytes())
    }

    @Test
    fun `AC-06 a readable preferences file reports nothing`() = runBlocking {
        val file = context.preferencesDataStoreFile("m1_app_boot_prefs_ok")
        file.delete()
        val reported = AtomicInteger()

        val repository = UserPreferencesRepository(openStore(file)) { reported.incrementAndGet() }
        repository.setThemeMode(ThemeMode.DARK)
        repository.setPayCycleStartDay(15)

        assertEquals(ThemeMode.DARK, repository.themeMode.first())
        assertEquals(15, repository.payCycleStartDay.first())
        assertEquals("a healthy store must never report a failure", 0, reported.get())
    }

    private suspend fun seedRealDatabase(): File {
        val database = Room
            .databaseBuilder(context, PersonalFinanceDatabase::class.java, databaseName)
            .addMigrations(*PersonalFinanceDatabase.MIGRATIONS)
            .allowMainThreadQueries()
            .build()
        RoomCategoryRepository(database).add(
            NewCategory(name = "Boot fixture", iconToken = "cart.fill", type = TransactionType.EXPENSE),
        )
        // Close so the WAL is folded in and the single file provably holds the row.
        database.close()
        return context.getDatabasePath(databaseName)
    }

    /** Overwrites page 1 in place, leaving the file's length and every later page alone. */
    private fun corruptFirstPage(file: File) {
        RandomAccessFile(file, "rw").use { raf ->
            raf.seek(0)
            raf.write(ByteArray(1024) { (it * 17 + 3).toByte() })
        }
    }

    private fun openStore(file: File): DataStore<Preferences> =
        StoreSession(file).also { session?.let { old -> runBlocking { old.close() } }; session = it }.store

    private class StoreSession(file: File) {
        private val job = SupervisorJob()
        private val scope = CoroutineScope(Dispatchers.IO + job)
        val store: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file }
        suspend fun close() = job.cancelAndJoin()
    }
}
