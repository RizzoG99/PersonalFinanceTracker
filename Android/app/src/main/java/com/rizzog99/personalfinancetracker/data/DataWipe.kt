package com.rizzog99.personalfinancetracker.data

import android.util.Log
import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import kotlin.coroutines.cancellation.CancellationException

/**
 * Settings > Delete all data, as frozen iOS `DataWipeService.swift:4-16` (#320).
 *
 * The ledger goes and the default categories come back in one Room transaction, so a failure leaves
 * everything as it was and the caller can truthfully say nothing changed. Deleting the rules is what
 * stops a recurrence from recreating erased transactions. Learned merchant mappings stay, as on iOS
 * (D-02). The "Not fixed" answers are cleared after the commit, as iOS does after `save()`; that
 * cannot be undone with the ledger, so its failure is logged, not reported: the data is already gone.
 */
suspend fun wipeAllData(
    database: PersonalFinanceDatabase,
    categoryRepository: CategoryRepository,
    dismissedPatterns: DismissedRecurrencePatternsRepository,
) {
    database.withTransaction {
        // Not clearAllTables(): it commits on its own, outside this transaction.
        WIPED_TABLES.forEach { database.openHelper.writableDatabase.execSQL("DELETE FROM `$it`") }
        categoryRepository.seedDefaultsIfEmpty()
    }
    try {
        dismissedPatterns.clear()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        Log.e("DataWipe", "Clearing dismissed recurrence answers failed", failure)
    }
}

/** Children before parents; `merchant_category_mappings` is deliberately absent (D-02). */
private val WIPED_TABLES = listOf(
    "transactions", "recurrence_rules", "goals", "credit_cards",
    "health_score_snapshots", "daily_forecast_cache", "categories",
)
