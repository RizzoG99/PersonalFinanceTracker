package com.rizzog99.personalfinancetracker.data.local

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import java.io.File
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * `AC-05`: a migration that cannot complete must leave the source database recoverable, and the app
 * must never fall back to destroying it.
 *
 * Two distinct failure modes, proven separately because they fail for different reasons:
 * a **missing** migration path (no `Migration` registered at all) and a **failing** migration
 * (registered, but its SQL throws).
 */
@RunWith(RobolectricTestRunner::class)
class RoomMigrationFailureTest {
    private val sourceName = "m1-migration-source.db"
    private val copyName = "m1-migration-copy.db"
    private lateinit var context: Context

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        PersonalFinanceDatabase::class.java,
    )

    private var openDatabase: PersonalFinanceDatabase? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(copyName)
    }

    @After
    fun tearDown() {
        openDatabase?.close()
        context.deleteDatabase(sourceName)
        context.deleteDatabase(copyName)
    }

    @Test
    fun `AC-05_1 a missing migration path refuses to open instead of destructively recreating the database`() = runBlocking {
        helper.createDatabase(sourceName, 1).use(MigrationFixtures::seedVersion1)
        val before = rowCensus(sourceName)
        val sizeBefore = context.getDatabasePath(sourceName).length()

        // The production builder never calls fallbackToDestructiveMigration. Without a registered
        // path from 1 to 3 that is the difference between "refuses to open" and "silently wipes".
        val withoutMigrations = Room
            .databaseBuilder(context, PersonalFinanceDatabase::class.java, sourceName)
            .allowMainThreadQueries()
            .build()
        val failure = runCatching { withoutMigrations.categoryDao().count() }.exceptionOrNull()
        withoutMigrations.close()

        assertTrue(
            "a missing migration must raise IllegalStateException, not recreate the schema: $failure",
            failure is IllegalStateException,
        )
        assertTrue(
            "the message must name the missing migration: ${failure?.message}",
            failure?.message?.contains("Migration didn't properly handle") == true ||
                failure?.message?.contains("A migration from 1 to 3 was required") == true,
        )

        // Measured, not inferred from the exception type: nothing was dropped or recreated.
        assertEquals("no table may lose rows", before, rowCensus(sourceName))
        assertEquals("the file must not be recreated", sizeBefore, context.getDatabasePath(sourceName).length())
        assertEquals("the database must still be at its source version", 1, userVersionOf(sourceName))

        // And the same file still upgrades cleanly once the real migrations are registered.
        assertEverySeededRecordIsExact(openProductionDatabase(sourceName))
    }

    @Test
    fun `AC-05_2 a failing migration leaves the copied source database intact and recoverable`() = runBlocking {
        helper.createDatabase(sourceName, 1).use(MigrationFixtures::seedVersion1)
        val sourceFile = context.getDatabasePath(sourceName)
        val copyFile = context.getDatabasePath(copyName)
        sourceFile.copyTo(copyFile, overwrite = true)

        val before = rowCensus(copyName)
        assertEquals("the copy must carry the source rows", rowCensus(sourceName), before)

        // The ALTER runs first and succeeds, so the "column is gone afterwards" assertion below
        // measures a rollback rather than a statement that never executed.
        val broken = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE categories ADD COLUMN normalizedName TEXT NOT NULL DEFAULT ''")
                db.execSQL("INSERT INTO table_that_does_not_exist (id) VALUES ('boom')")
            }
        }
        val failing = Room
            .databaseBuilder(context, PersonalFinanceDatabase::class.java, copyName)
            .addMigrations(broken, PersonalFinanceDatabase.MIGRATION_2_3)
            .allowMainThreadQueries()
            .build()
        val failure = runCatching { failing.categoryDao().count() }.exceptionOrNull()
        failing.close()

        assertTrue("opening through a failing migration must throw: $failure", failure != null)

        // Rollback: the half-applied ALTER is gone, the version is untouched, every row survives.
        assertEquals("a failed migration may not change any row", before, rowCensus(copyName))
        assertEquals("a failed migration may not advance the version", 1, userVersionOf(copyName))
        assertTrue(
            "the rolled-back column must not be left behind",
            !columnNamesOf(copyName, "categories").contains("normalizedName"),
        )
        assertTrue("the source file must be untouched", sourceFile.exists())
        assertEquals("the source rows must be untouched", before, rowCensus(sourceName))

        // Recoverability is the user-facing promise: the same copied file opens through the real
        // migration set afterwards with every record accessible.
        assertEverySeededRecordIsExact(openProductionDatabase(copyName))
        assertEquals(
            3,
            RoomTransactionRepository(requireNotNull(openDatabase)).observeAll().first().size,
        )
    }

    private fun openProductionDatabase(name: String): PersonalFinanceDatabase {
        openDatabase?.close()
        return Room.databaseBuilder(context, PersonalFinanceDatabase::class.java, name)
            .addMigrations(*PersonalFinanceDatabase.MIGRATIONS)
            .allowMainThreadQueries()
            .build()
            .also { openDatabase = it }
    }

    /** Row counts per table read straight from the file, bypassing Room entirely. */
    private fun rowCensus(name: String): Map<String, Int> = readRaw(name) { db ->
        val tables = db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
            null,
        ).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }
        tables.sorted().associateWith { table ->
            db.rawQuery("SELECT COUNT(*) FROM `$table`", null).use {
                it.moveToFirst()
                it.getInt(0)
            }
        }
    }

    private fun userVersionOf(name: String): Int = readRaw(name) { it.version }

    private fun columnNamesOf(name: String, table: String): List<String> = readRaw(name) { db ->
        db.rawQuery("PRAGMA table_info(`$table`)", null).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(1)) }
        }
    }

    private fun <T> readRaw(name: String, read: (SQLiteDatabase) -> T): T {
        val file: File = context.getDatabasePath(name)
        return SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use(read)
    }
}
