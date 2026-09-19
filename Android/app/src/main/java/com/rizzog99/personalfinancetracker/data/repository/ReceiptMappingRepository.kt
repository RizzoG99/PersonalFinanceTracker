package com.rizzog99.personalfinancetracker.data.repository

import com.rizzog99.personalfinancetracker.data.local.MerchantCategoryMappingEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import java.util.Locale

interface ReceiptMappingRepository {
    suspend fun categoryIdFor(merchant: String): String?
    suspend fun remember(merchant: String, categoryId: String)
}

class RoomReceiptMappingRepository(
    private val database: PersonalFinanceDatabase,
) : ReceiptMappingRepository {
    override suspend fun categoryIdFor(merchant: String): String? =
        database.merchantCategoryMappingDao().categoryIdFor(merchant.normalizedMerchant())

    override suspend fun remember(merchant: String, categoryId: String) {
        database.merchantCategoryMappingDao().upsert(
            MerchantCategoryMappingEntity(
                normalizedMerchant = merchant.normalizedMerchant(),
                categoryId = categoryId,
            ),
        )
    }
}

/**
 * Same normalization on write and read, matching the frozen `ReceiptCategoryInferrer.normalize`:
 * trim and lowercase, nothing else. Accents are part of the merchant name — folding them made
 * "Caffè Roma" and "Caffe Roma" collide on the primary key, so learning one destroyed the other.
 */
fun String.normalizedMerchant(): String = trim(Char::isIosWhitespace).lowercase(Locale.ROOT)

/**
 * The frozen side trims `CharacterSet.whitespaces`, which is Unicode category `Zs` plus tab —
 * newlines are *not* in it. Kotlin's `String.trim()` also strips them, so a merchant string carrying
 * one would normalize to a different primary key on each platform. Nothing at this repository's entry
 * points guarantees a single-line merchant, so the trimming has to match rather than rely on callers.
 */
private fun Char.isIosWhitespace(): Boolean =
    this == '\t' || Character.getType(this) == Character.SPACE_SEPARATOR.toInt()
