package com.rizzog99.personalfinancetracker.data

import android.util.Log
import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * Settings > Delete all data, as frozen iOS `DataWipeService.swift:4-16` (#320).
 *
 * The ledger goes and the default categories come back in one Room transaction. Deleting the rules
 * is what stops a recurrence from recreating erased transactions. Learned merchant mappings stay, as
 * on iOS (D-02).
 *
 * The "Not fixed" answers live in DataStore, outside that transaction, and must not outlive the
 * ledger (they would hide suggestions on the next import). So they are cleared *first*, and put back
 * if the transaction then rolls back. Every throw from here therefore means nothing was erased, and
 * the caller can say so.
 */
suspend fun wipeAllData(
    database: PersonalFinanceDatabase,
    categoryRepository: CategoryRepository,
    dismissedPatterns: DismissedRecurrencePatternsRepository,
) = withContext(NonCancellable) {
    // One unit: leaving Settings mid-erase (its scope cancels) must not stop between the two stores.
    val answers = dismissedPatterns.all()
    dismissedPatterns.clear()
    try {
        database.withTransaction {
            // Not clearAllTables(): it commits on its own, outside this transaction.
            WIPED_TABLES.forEach { database.openHelper.writableDatabase.execSQL("DELETE FROM `$it`") }
            categoryRepository.seedDefaultsIfEmpty()
        }
    } catch (failure: Exception) {
        try {
            dismissedPatterns.restore(answers)
        } catch (restoreFailure: Exception) {
            // ponytail: D-07 — the ledger is intact; at worst a few suggestions are offered again.
            Log.e("DataWipe", "Restoring dismissed recurrence answers failed", restoreFailure)
        }
        throw failure
    }
}

/** Children before parents; `merchant_category_mappings` is deliberately absent (D-02). */
private val WIPED_TABLES = listOf(
    "transactions", "recurrence_rules", "goals", "credit_cards",
    "health_score_snapshots", "daily_forecast_cache", "categories",
)
