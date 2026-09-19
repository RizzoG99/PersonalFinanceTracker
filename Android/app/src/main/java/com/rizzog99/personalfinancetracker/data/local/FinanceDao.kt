package com.rizzog99.personalfinancetracker.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface TransactionDao {
    @Query("SELECT * FROM transactions ORDER BY timestampEpochMillis DESC")
    fun observeAll(): Flow<List<TransactionEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(transaction: TransactionEntity)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertAll(transactions: List<TransactionEntity>)

    @Query("DELETE FROM transactions WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM transactions WHERE recurrenceRuleId = :recurrenceRuleId AND timestampEpochMillis >= :cutoffEpochMillis")
    suspend fun deleteOccurrencesFrom(recurrenceRuleId: String, cutoffEpochMillis: Long)

    @Query("DELETE FROM transactions WHERE recurrenceRuleId = :recurrenceRuleId AND timestampEpochMillis > :cutoffEpochMillis")
    suspend fun deleteOccurrencesAfter(recurrenceRuleId: String, cutoffEpochMillis: Long)

    @Query("DELETE FROM transactions")
    suspend fun deleteAll()
}

@Dao
interface RecurrenceRuleDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(rule: RecurrenceRuleEntity)

    @Query("UPDATE recurrence_rules SET endDateEpochMillis = :endDateEpochMillis WHERE id = :id")
    suspend fun close(id: String, endDateEpochMillis: Long)

    @Query("SELECT * FROM recurrence_rules WHERE id = :id")
    suspend fun get(id: String): RecurrenceRuleEntity?

    @Query("SELECT * FROM recurrence_rules WHERE endDateEpochMillis IS NULL OR endDateEpochMillis >= :throughEpochMillis")
    suspend fun getActive(throughEpochMillis: Long): List<RecurrenceRuleEntity>

    @Query("UPDATE recurrence_rules SET lastMaterializedDateEpochMillis = :lastMaterializedDateEpochMillis WHERE id = :id")
    suspend fun updateLastMaterializedDate(id: String, lastMaterializedDateEpochMillis: Long)

    @Update(onConflict = OnConflictStrategy.ABORT)
    suspend fun update(rule: RecurrenceRuleEntity)

    @Query("UPDATE recurrence_rules SET categoryId = NULL WHERE categoryId = :categoryId")
    suspend fun clearCategoryReference(categoryId: String)
}

@Dao
interface CreditCardDao {
    @Query("SELECT * FROM credit_cards ORDER BY name COLLATE NOCASE")
    fun observeAll(): Flow<List<CreditCardEntity>>

    @Query("SELECT * FROM credit_cards WHERE id = :id")
    suspend fun get(id: String): CreditCardEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(card: CreditCardEntity)

    @Update(onConflict = OnConflictStrategy.ABORT)
    suspend fun update(card: CreditCardEntity)

    @Query("DELETE FROM credit_cards WHERE id = :id")
    suspend fun delete(id: String)
}

@Dao
interface HealthScoreSnapshotDao {
    @Query("SELECT * FROM health_score_snapshots ORDER BY timestampEpochMillis DESC LIMIT :limit")
    suspend fun recent(limit: Int): List<HealthScoreSnapshotEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(snapshot: HealthScoreSnapshotEntity)
}

@Dao
interface DailyForecastCacheDao {
    @Query("SELECT * FROM daily_forecast_cache LIMIT 1")
    suspend fun get(): DailyForecastCacheEntity?

    @Query("SELECT COUNT(*) FROM daily_forecast_cache")
    suspend fun count(): Int

    /**
     * The frozen `TransactionActor.saveForecastCache` deletes every existing row before inserting,
     * so the cache is a singleton. The fixed primary key plus REPLACE gives the same guarantee.
     */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(cache: DailyForecastCacheEntity)

    @Query("DELETE FROM daily_forecast_cache")
    suspend fun clear()
}

@Dao
interface MerchantCategoryMappingDao {
    @Query("SELECT categoryId FROM merchant_category_mappings WHERE normalizedMerchant = :normalizedMerchant")
    suspend fun categoryIdFor(normalizedMerchant: String): String?

    @Query("SELECT COUNT(*) FROM merchant_category_mappings")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(mapping: MerchantCategoryMappingEntity)
}

@Dao
interface CategoryDao {
    @Query("SELECT * FROM categories ORDER BY name COLLATE NOCASE")
    fun observeAll(): Flow<List<CategoryEntity>>

    @Query("SELECT COUNT(*) FROM categories")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(category: CategoryEntity)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertAll(categories: List<CategoryEntity>)

    @Update(onConflict = OnConflictStrategy.ABORT)
    suspend fun update(category: CategoryEntity)

    @Query("DELETE FROM categories WHERE id = :id")
    suspend fun delete(id: String)
}

@Dao
interface GoalDao {
    @Query("SELECT * FROM goals ORDER BY createdAtEpochMillis ASC")
    fun observeAll(): Flow<List<GoalEntity>>

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(goal: GoalEntity)

    @Update(onConflict = OnConflictStrategy.ABORT)
    suspend fun update(goal: GoalEntity)

    @Query("DELETE FROM goals WHERE id = :id")
    suspend fun delete(id: String)
}
