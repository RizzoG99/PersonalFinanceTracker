package com.rizzog99.personalfinancetracker.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "categories",
    indices = [Index(value = ["normalizedName", "type"], unique = true)],
)
data class CategoryEntity(
    @PrimaryKey val id: String,
    val name: String,
    val normalizedName: String,
    val iconToken: String,
    val type: String,
    val colorToken: String,
    val monthlyBudgetDecimal: String?,
    val currencyCode: String,
)

@Entity(tableName = "goals")
data class GoalEntity(
    @PrimaryKey val id: String,
    val name: String,
    val targetAmountDecimal: String,
    val deadlineEpochMillis: Long?,
    val colorToken: String,
    val iconToken: String,
    val createdAtEpochMillis: Long,
)

@Entity(tableName = "recurrence_rules")
data class RecurrenceRuleEntity(
    @PrimaryKey val id: String,
    val frequency: String,
    val interval: Int,
    val startDateEpochMillis: Long,
    val endDateEpochMillis: Long?,
    val lastMaterializedDateEpochMillis: Long?,
    val amountDecimal: String,
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val currencyCode: String,
    val goalId: String?,
)

@Entity(
    tableName = "transactions",
    foreignKeys = [
        ForeignKey(entity = CategoryEntity::class, parentColumns = ["id"], childColumns = ["categoryId"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = GoalEntity::class, parentColumns = ["id"], childColumns = ["goalId"], onDelete = ForeignKey.SET_NULL),
        ForeignKey(entity = RecurrenceRuleEntity::class, parentColumns = ["id"], childColumns = ["recurrenceRuleId"], onDelete = ForeignKey.SET_NULL),
    ],
    indices = [Index("timestampEpochMillis"), Index("categoryId"), Index("goalId"), Index("recurrenceRuleId")],
)
data class TransactionEntity(
    @PrimaryKey val id: String,
    val timestampEpochMillis: Long,
    val amountDecimal: String,
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val currencyCode: String,
    val goalId: String?,
    val recurrenceRuleId: String?,
)

@Entity(tableName = "health_score_snapshots")
data class HealthScoreSnapshotEntity(
    @PrimaryKey val id: String,
    val timestampEpochMillis: Long,
    val score: Int,
    val savingsScore: Int,
    val stabilityScore: Int,
    val adherenceScore: Int,
    val subscriptionScore: Int,
)

@Entity(tableName = "daily_forecast_cache")
data class DailyForecastCacheEntity(
    @PrimaryKey val id: Int = SINGLETON_ID,
    val monthKey: String,
    val computedUpToDay: Int,
    val dayValuesJson: String,
) {
    companion object { const val SINGLETON_ID = 1 }
}

@Entity(tableName = "merchant_category_mappings")
data class MerchantCategoryMappingEntity(
    @PrimaryKey val normalizedMerchant: String,
    val categoryId: String,
)
