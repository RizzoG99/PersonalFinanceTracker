package com.rizzog99.personalfinancetracker.data.local

import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory

/**
 * Stops the platform from deleting the user's database when SQLite reports corruption (#130).
 *
 * Room builds its helper through [FrameworkSQLiteOpenHelperFactory], and the callback it installs
 * inherits `SupportSQLiteOpenHelper.Callback.onCorruption`, whose implementation **deletes the
 * database file**. Measured on `emulator-5554` at `c8d186d`: one damaged page turned a
 * 106,496-byte database holding every transaction, goal, recurrence rule, credit card, and health
 * snapshot into a fresh 4,096-byte empty schema, logged only as
 * `W SupportSQLite: deleting the database file`, and shown to the user as "Start tracking".
 *
 * This is a different path from a migration failure. `PersonalFinanceApplication` already declines
 * `fallbackToDestructiveMigration()`, which covers a *version* mismatch (`RoomMigrationFailureTest`)
 * and does nothing at all for corruption.
 *
 * So the whole factory exists to override exactly one method. Every other callback member
 * delegates to Room's own — `onOpen` in particular carries Room's identity-hash check, and a
 * callback that dropped it would break ordinary launches, not just damaged ones.
 */
class NonDestructiveOpenHelperFactory(
    private val onCorruption: (String?) -> Unit,
    private val delegate: SupportSQLiteOpenHelper.Factory = FrameworkSQLiteOpenHelperFactory(),
) : SupportSQLiteOpenHelper.Factory {

    override fun create(configuration: SupportSQLiteOpenHelper.Configuration): SupportSQLiteOpenHelper =
        delegate.create(
            SupportSQLiteOpenHelper.Configuration.builder(configuration.context)
                .name(configuration.name)
                .callback(PreservingCallback(configuration.callback, onCorruption))
                .noBackupDirectory(configuration.useNoBackupDirectory)
                .allowDataLossOnRecovery(configuration.allowDataLossOnRecovery)
                .build(),
        )

    private class PreservingCallback(
        private val delegate: SupportSQLiteOpenHelper.Callback,
        private val onCorruption: (String?) -> Unit,
    ) : SupportSQLiteOpenHelper.Callback(delegate.version) {

        override fun onConfigure(db: SupportSQLiteDatabase) = delegate.onConfigure(db)

        override fun onCreate(db: SupportSQLiteDatabase) = delegate.onCreate(db)

        override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) =
            delegate.onUpgrade(db, oldVersion, newVersion)

        override fun onDowngrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) =
            delegate.onDowngrade(db, oldVersion, newVersion)

        override fun onOpen(db: SupportSQLiteDatabase) = delegate.onOpen(db)

        /**
         * Deliberately does not call through: the inherited implementation is the deletion. The
         * file is left exactly as it is so a backup tool, a support request, or a later fix can
         * still reach it, and the caller is told so the UI can explain itself instead of rendering
         * an empty account.
         *
         * Whatever SQLite threw still propagates — refusing to delete is not the same as pretending
         * the database opened.
         */
        override fun onCorruption(db: SupportSQLiteDatabase) {
            onCorruption(runCatching { db.path }.getOrNull())
        }
    }
}
