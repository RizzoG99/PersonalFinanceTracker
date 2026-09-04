package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.CategoryDao
import com.rizzog99.personalfinancetracker.data.local.CategoryEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.category.CategoryNameValidator
import com.rizzog99.personalfinancetracker.domain.category.DefaultCategories
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface CategoryRepository {
    fun observeAll(): Flow<List<FinanceCategory>>
    suspend fun add(category: NewCategory): FinanceCategory
    suspend fun delete(id: String)
    suspend fun seedDefaultsIfEmpty()
}

class RoomCategoryRepository(
    private val database: PersonalFinanceDatabase,
) : CategoryRepository {
    private val dao: CategoryDao = database.categoryDao()

    override fun observeAll(): Flow<List<FinanceCategory>> = dao.observeAll().map { entities ->
        entities.map(CategoryEntity::toDomain)
    }

    override suspend fun add(category: NewCategory): FinanceCategory = database.withTransaction {
        category.toEntity().also { entity -> dao.insert(entity) }.toDomain()
    }

    override suspend fun delete(id: String) {
        dao.delete(id)
    }

    override suspend fun seedDefaultsIfEmpty() {
        database.withTransaction {
            if (dao.count() == 0) {
                dao.insertAll(DefaultCategories.all.map(NewCategory::toEntity))
            }
        }
    }
}

private fun NewCategory.toEntity(): CategoryEntity {
    val trimmedName = name.trim()
    require(trimmedName.isNotEmpty()) { "A category name cannot be blank." }
    require(CategoryNameValidator.isValid(trimmedName)) { "A category name contains unsupported characters." }
    monthlyBudget?.let { require(it >= java.math.BigDecimal.ZERO) { "A category budget cannot be negative." } }

    return CategoryEntity(
        id = UUID.nameUUIDFromBytes("${type.name}:$trimmedName".toByteArray(StandardCharsets.UTF_8)).toString(),
        name = trimmedName,
        normalizedName = CategoryNameValidator.normalized(trimmedName),
        iconToken = iconToken,
        type = type.storageValue,
        colorToken = colorToken,
        monthlyBudgetDecimal = monthlyBudget?.let(MoneyCodec::encode),
        currencyCode = currencyCode,
    )
}

private fun CategoryEntity.toDomain() = FinanceCategory(
    id = id,
    name = name,
    iconToken = iconToken,
    type = TransactionType.fromStorage(type),
    colorToken = colorToken,
    monthlyBudget = monthlyBudgetDecimal?.let(MoneyCodec::decode),
    currencyCode = currencyCode,
)

private val TransactionType.storageValue: String
    get() = name.lowercase()

private fun TransactionType.Companion.fromStorage(value: String): TransactionType = when (value) {
    "income" -> TransactionType.INCOME
    "expense" -> TransactionType.EXPENSE
    else -> error("Unknown transaction type: $value")
}
