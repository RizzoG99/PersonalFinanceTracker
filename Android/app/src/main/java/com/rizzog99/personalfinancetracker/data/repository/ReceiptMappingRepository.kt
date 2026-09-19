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
fun String.normalizedMerchant(): String = trim().lowercase(Locale.ROOT)
