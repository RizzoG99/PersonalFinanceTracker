package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.GoalDao
import com.rizzog99.personalfinancetracker.data.local.GoalEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface GoalRepository {
    fun observeAll(): Flow<List<FinanceGoal>>
    suspend fun add(goal: NewGoal): FinanceGoal
    suspend fun update(goal: FinanceGoal): FinanceGoal
    suspend fun delete(id: String)
}

class RoomGoalRepository(
    private val database: PersonalFinanceDatabase,
) : GoalRepository {
    private val dao: GoalDao = database.goalDao()

    override fun observeAll(): Flow<List<FinanceGoal>> = dao.observeAll().map { goals ->
        goals.map(GoalEntity::toDomain)
    }

    override suspend fun add(goal: NewGoal): FinanceGoal = database.withTransaction {
        goal.toEntity().also { dao.insert(it) }.toDomain()
    }

    override suspend fun update(goal: FinanceGoal): FinanceGoal = database.withTransaction {
        goal.toEntity().also { dao.update(it) }.toDomain()
    }

    override suspend fun delete(id: String) {
        dao.delete(id)
    }
}

private fun NewGoal.toEntity(): GoalEntity {
    val trimmedName = name.trim()
    require(trimmedName.isNotEmpty()) { "A goal name cannot be blank." }
    require(targetAmount > java.math.BigDecimal.ZERO) { "A goal target must be greater than zero." }

    return GoalEntity(
        id = UUID.randomUUID().toString(),
        name = trimmedName,
        targetAmountDecimal = MoneyCodec.encode(targetAmount),
        deadlineEpochMillis = deadline?.toEpochMilli(),
        colorToken = colorToken,
        iconToken = iconToken,
        createdAtEpochMillis = Instant.now().toEpochMilli(),
    )
}

private fun FinanceGoal.toEntity(): GoalEntity {
    val trimmedName = name.trim()
    require(trimmedName.isNotEmpty()) { "A goal name cannot be blank." }
    require(targetAmount > java.math.BigDecimal.ZERO) { "A goal target must be greater than zero." }

    return GoalEntity(
        id = id,
        name = trimmedName,
        targetAmountDecimal = MoneyCodec.encode(targetAmount),
        deadlineEpochMillis = deadline?.toEpochMilli(),
        colorToken = colorToken,
        iconToken = iconToken,
        createdAtEpochMillis = createdAt.toEpochMilli(),
    )
}

private fun GoalEntity.toDomain() = FinanceGoal(
    id = id,
    name = name,
    targetAmount = MoneyCodec.decode(targetAmountDecimal),
    deadline = deadlineEpochMillis?.let(Instant::ofEpochMilli),
    colorToken = colorToken,
    iconToken = iconToken,
    createdAt = Instant.ofEpochMilli(createdAtEpochMillis),
)
