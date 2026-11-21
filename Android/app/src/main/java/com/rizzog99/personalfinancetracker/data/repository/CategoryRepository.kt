package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.CategoryDao
import com.rizzog99.personalfinancetracker.data.local.CategoryEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.local.UnlinkedRow
import com.rizzog99.personalfinancetracker.domain.category.CategoryNameValidator
import com.rizzog99.personalfinancetracker.domain.category.DefaultCategories
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

interface CategoryRepository {
    fun observeAll(): Flow<List<FinanceCategory>>
    suspend fun add(category: NewCategory): FinanceCategory
    suspend fun update(category: FinanceCategory): FinanceCategory
    suspend fun delete(id: String)
    suspend fun seedDefaultsIfEmpty()

    /** Idempotent (#292): links unlinked rows whose label names a category of their type, then gives
     * every linked transaction and rule its category's current name. Returns the rows changed. */
    suspend fun repairLinks(): Int
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

    /** A rename carries the new name onto its transactions and rules in the same transaction (#292, iOS
     * `TransactionActor.renameCategory`), so lists, filters and charts never split it in two. */
    override suspend fun update(category: FinanceCategory): FinanceCategory = database.withTransaction {
        category.toUpdatedEntity().also { entity ->
            dao.update(entity)
            dao.syncTransactionLabels()
            dao.syncRuleLabels()
        }.toDomain()
    }

    override suspend fun repairLinks(): Int = database.withTransaction {
        val idByKey = dao.observeAll().first().associate { (it.normalizedName to it.type) to it.id }
        link(dao.unlinkedTransactions(), idByKey, dao::linkTransactions) +
            link(dao.unlinkedRules(), idByKey, dao::linkRules) +
            dao.syncTransactionLabels() +
            dao.syncRuleLabels()
    }

    /**
     * Links each row only to the category with exactly its name (trimmed, case-insensitive) and its
     * amount's type; a blank label means Other. Anything else is left as it is: never a guess across
     * income and expense, never a fuzzy match (#292 D-01, D-02).
     */
    private suspend fun link(
        rows: List<UnlinkedRow>,
        idByKey: Map<Pair<String, String>, String>,
        update: suspend (categoryId: String, ids: List<String>) -> Int,
    ): Int {
        var changed = 0
        rows.groupBy { row ->
            val name = CategoryNameValidator.normalized(row.categoryLabel).ifEmpty { "other" }
            idByKey[name to if (row.amountDecimal.startsWith("-")) "expense" else "income"]
        }.forEach { (categoryId, matched) ->
            // ponytail: 500 ids per statement stays under SQLite's 999-variable limit (API 26).
            if (categoryId != null) matched.map(UnlinkedRow::id).chunked(500).forEach { changed += update(categoryId, it) }
        }
        return changed
    }

    override suspend fun delete(id: String) {
        database.withTransaction {
            database.recurrenceRuleDao().clearCategoryReference(id)
            dao.delete(id)
        }
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

private fun FinanceCategory.toUpdatedEntity(): CategoryEntity {
    val trimmedName = name.trim()
    require(trimmedName.isNotEmpty()) { "A category name cannot be blank." }
    require(CategoryNameValidator.isValid(trimmedName)) { "A category name contains unsupported characters." }
    monthlyBudget?.let { require(it >= java.math.BigDecimal.ZERO) { "A category budget cannot be negative." } }

    return CategoryEntity(
        id = id,
        name = trimmedName,
        normalizedName = CategoryNameValidator.normalized(trimmedName),
        iconToken = iconToken,
        type = type.storageValue,
        colorToken = colorToken,
        monthlyBudgetDecimal = monthlyBudget?.let(MoneyCodec::encode),
        currencyCode = currencyCode,
    )
}

private val TransactionType.storageValue: String
    get() = name.lowercase()

private fun TransactionType.Companion.fromStorage(value: String): TransactionType = when (value) {
    "income" -> TransactionType.INCOME
    "expense" -> TransactionType.EXPENSE
    else -> error("Unknown transaction type: $value")
}
