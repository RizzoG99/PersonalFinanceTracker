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
