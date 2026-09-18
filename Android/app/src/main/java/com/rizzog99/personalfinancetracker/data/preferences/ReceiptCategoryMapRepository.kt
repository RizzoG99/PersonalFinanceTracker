package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.rizzog99.personalfinancetracker.domain.receipt.ReceiptCategoryConcept
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.receiptCategoryDataStore by preferencesDataStore(name = "receipt_category_concepts")

/**
 * The user's own answer to "which of my categories is eating out?".
 *
 * Stores concept key -> category id. Ids rather than names, so renaming a category keeps its
 * pairing — which is the whole point of the feature.
 *
 * DataStore rather than Room, mirroring iOS's use of UserDefaults for the same map: it is a handful
 * of settings, it follows [UserPreferencesRepository], and it needs no schema.
 */
class ReceiptCategoryMapRepository(private val context: Context) {

    /** concept key -> category id, for every pairing the user has set. */
    val pairings: Flow<Map<String, String>> = context.receiptCategoryDataStore.data.map { prefs ->
        ReceiptCategoryConcept.entries.mapNotNull { concept ->
            prefs[stringPreferencesKey(concept.key)]?.let { concept.key to it }
        }.toMap()
    }

    suspend fun setCategoryId(categoryId: String?, concept: ReceiptCategoryConcept) {
        context.receiptCategoryDataStore.edit { prefs ->
            val key = stringPreferencesKey(concept.key)
            if (categoryId == null) prefs.remove(key) else prefs[key] = categoryId
        }
    }

    /**
     * Drops pairings whose category no longer exists, so a deleted category does not leave a
     * pairing that silently matches nothing.
     */
    suspend fun prune(liveCategoryIds: Set<String>) {
        context.receiptCategoryDataStore.edit { prefs ->
            ReceiptCategoryConcept.entries.forEach { concept ->
                val key = stringPreferencesKey(concept.key)
                if (prefs[key]?.let { it !in liveCategoryIds } == true) prefs.remove(key)
            }
        }
    }
}

/**
 * Resolves a stored pairing for [conceptKey], falling back from `gas` to `transport`.
 *
 * `gas` was split out of `transport` when the synonym table was aligned with iOS, so a fuel receipt
 * now asks for a concept nobody has ever been shown a picker for. Someone who paired the old
 * combined "Transport & fuel" row keeps that answer until they pick a Fuel category of their own.
 */
fun Map<String, String>.categoryIdForConcept(conceptKey: String): String? =
    this[conceptKey] ?: if (conceptKey == ReceiptCategoryConcept.GAS.key) {
        this[ReceiptCategoryConcept.TRANSPORT.key]
    } else {
        null
    }
