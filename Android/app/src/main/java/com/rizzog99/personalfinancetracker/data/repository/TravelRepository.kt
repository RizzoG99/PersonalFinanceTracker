package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.local.TravelEntity
import com.rizzog99.personalfinancetracker.domain.travel.FinanceTravel
import java.time.Clock
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

/** Travels (#284), frozen iOS `TransactionActor` travel methods. */
interface TravelRepository {
    /** Newest first, as iOS `fetchTravels` sorts by `createdAt` descending. */
    fun observeAll(): Flow<List<FinanceTravel>>
    suspend fun add(name: String, symbolName: String): FinanceTravel
    suspend fun update(id: String, name: String, symbolName: String)

    /** Deletes the folder, never its contents: members are untagged in the same transaction. */
    suspend fun delete(id: String)

    /** Tags (or, with `null`, untags) [ids] in one transaction. */
    suspend fun assign(ids: List<String>, travelId: String?)

    /** Creates a travel and moves [ids] into it in one transaction (iOS `addTravelAndAssignSelection`). */
    suspend fun addAndAssign(name: String, symbolName: String, ids: List<String>): FinanceTravel

    /** For screens built without travels (older tests, previews). Emits one empty list so `combine` still loads. */
    object None : TravelRepository {
        override fun observeAll(): Flow<List<FinanceTravel>> = flowOf(emptyList())
        override suspend fun add(name: String, symbolName: String) = error("No travel repository")
        override suspend fun update(id: String, name: String, symbolName: String) = Unit
        override suspend fun delete(id: String) = Unit
        override suspend fun assign(ids: List<String>, travelId: String?) = Unit
        override suspend fun addAndAssign(name: String, symbolName: String, ids: List<String>) = error("No travel repository")
    }
}

class RoomTravelRepository(
    private val database: PersonalFinanceDatabase,
    private val clock: Clock = Clock.systemUTC(),
) : TravelRepository {
    private val travels = database.travelDao()
    private val transactions = database.transactionDao()

    // Stored as epoch millis, so created at millis: the returned travel then equals the stored one.
    private fun now() = Instant.now(clock).truncatedTo(ChronoUnit.MILLIS)

    override fun observeAll(): Flow<List<FinanceTravel>> = travels.observeAll().map { rows -> rows.map(TravelEntity::toDomain) }

    override suspend fun add(name: String, symbolName: String): FinanceTravel {
        val travel = FinanceTravel(UUID.randomUUID().toString(), name.trim(), symbolName, now())
        travels.insert(travel.toEntity())
        return travel
    }

    override suspend fun update(id: String, name: String, symbolName: String) = travels.update(id, name.trim(), symbolName)

    override suspend fun delete(id: String) = database.withTransaction {
        transactions.clearTravel(id)
        travels.delete(id)
    }

    override suspend fun assign(ids: List<String>, travelId: String?) = database.withTransaction {
        // ponytail: chunked for SQLite's 999-bound-variable limit on older Android versions.
        ids.chunked(500).forEach { transactions.setTravel(it, travelId) }
    }

    override suspend fun addAndAssign(name: String, symbolName: String, ids: List<String>): FinanceTravel =
        database.withTransaction {
            val travel = FinanceTravel(UUID.randomUUID().toString(), name.trim(), symbolName, now())
            travels.insert(travel.toEntity())
            ids.chunked(500).forEach { transactions.setTravel(it, travel.id) }
            travel
        }
}

private fun TravelEntity.toDomain() = FinanceTravel(id, name, symbolName, Instant.ofEpochMilli(createdAtEpochMillis))

private fun FinanceTravel.toEntity() = TravelEntity(id, name, symbolName, createdAt.toEpochMilli())
