package com.rizzog99.personalfinancetracker.data.repository

import com.rizzog99.personalfinancetracker.data.local.MerchantCategoryMappingEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import java.text.Normalizer
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

fun String.normalizedMerchant(): String = Normalizer.normalize(this, Normalizer.Form.NFD)
    .replace("\\p{M}".toRegex(), "")
    .trim()
    .lowercase(Locale.ROOT)
