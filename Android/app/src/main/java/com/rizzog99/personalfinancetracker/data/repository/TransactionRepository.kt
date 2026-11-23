package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.local.TransactionDao
import com.rizzog99.personalfinancetracker.data.local.TransactionEntity
import com.rizzog99.personalfinancetracker.domain.import.ImportReconciler
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface TransactionRepository {
    fun observeAll(): Flow<List<FinanceTransaction>>
    suspend fun upsert(transaction: FinanceTransaction)
    suspend fun insertBatch(transactions: List<FinanceTransaction>)

    /** Saves the [transactions] not already in the ledger ([ImportReconciler]), reading and writing in
     * one transaction so a concurrent writer (start-up materialization) can't slip a row in between (#314).
     * Returns the rows saved. */
    suspend fun insertNew(transactions: List<FinanceTransaction>): List<FinanceTransaction>
    suspend fun delete(id: String)
    suspend fun deleteThisAndFuture(recurrenceRuleId: String, cutoff: Instant)

    /** Bulk edit and its Undo (#285): every row or none, in one write, so the ledger refreshes once. */
    suspend fun upsertAll(transactions: List<FinanceTransaction>)

    /** Bulk delete (#285): every row or none, in one write. */
    suspend fun deleteAll(ids: List<String>)
}

class RoomTransactionRepository(
    private val database: PersonalFinanceDatabase,
) : TransactionRepository {
    private val dao: TransactionDao = database.transactionDao()

    override fun observeAll(): Flow<List<FinanceTransaction>> = dao.observeAll().map { entities ->
        entities.map(TransactionEntity::toDomain)
    }

    override suspend fun upsert(transaction: FinanceTransaction) {
        dao.upsert(transaction.toEntity())
    }

    override suspend fun insertBatch(transactions: List<FinanceTransaction>) {
        database.withTransaction {
            dao.insertAll(transactions.map(FinanceTransaction::toEntity))
        }
    }

    override suspend fun insertNew(transactions: List<FinanceTransaction>): List<FinanceTransaction> =
        database.withTransaction {
            val (fresh, _) = ImportReconciler.split(transactions, dao.getAll().map(TransactionEntity::toDomain))
            dao.insertAll(fresh.map(FinanceTransaction::toEntity))
            fresh
        }

    override suspend fun delete(id: String) {
        dao.delete(id)
    }

    override suspend fun upsertAll(transactions: List<FinanceTransaction>) {
        database.withTransaction { dao.upsertAll(transactions.map(FinanceTransaction::toEntity)) }
    }

    override suspend fun deleteAll(ids: List<String>) {
        // ponytail: chunked for SQLite's 999-bound-variable limit on older Android versions.
        database.withTransaction { ids.chunked(500).forEach { dao.deleteByIds(it) } }
    }

    override suspend fun deleteThisAndFuture(recurrenceRuleId: String, cutoff: Instant) {
        database.withTransaction {
            database.recurrenceRuleDao().close(
                id = recurrenceRuleId,
                endDateEpochMillis = cutoff.minusMillis(1).toEpochMilli(),
            )
            dao.deleteOccurrencesFrom(recurrenceRuleId, cutoff.toEpochMilli())
        }
    }
}

internal fun TransactionEntity.toDomain() = FinanceTransaction(
    id = id,
    timestamp = Instant.ofEpochMilli(timestampEpochMillis),
    amount = MoneyCodec.decode(amountDecimal),
    note = note,
    categoryLabel = categoryLabel,
    categoryId = categoryId,
    currencyCode = currencyCode,
    goalId = goalId,
    recurrenceRuleId = recurrenceRuleId,
)

private fun FinanceTransaction.toEntity() = TransactionEntity(
    id = id,
    timestampEpochMillis = timestamp.toEpochMilli(),
    amountDecimal = MoneyCodec.encode(amount),
    note = note,
    categoryLabel = categoryLabel,
    categoryId = categoryId,
    currencyCode = currencyCode,
    goalId = goalId,
    recurrenceRuleId = recurrenceRuleId,
)
