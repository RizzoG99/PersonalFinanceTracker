package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.local.RecurrenceRuleEntity
import com.rizzog99.personalfinancetracker.data.local.TransactionEntity
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceOccurrenceCalculator
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

interface RecurrenceRepository {
    suspend fun createAndMaterialize(rule: NewRecurrenceRule): RecurrenceRule
    suspend fun materializeDue(through: Instant = Instant.now(), zoneId: ZoneId = ZoneId.systemDefault())
}

class RoomRecurrenceRepository(
    private val database: PersonalFinanceDatabase,
) : RecurrenceRepository {
    override suspend fun createAndMaterialize(rule: NewRecurrenceRule): RecurrenceRule {
        require(rule.interval > 0) { "A recurrence interval must be positive." }
        val entity = rule.toEntity()
        database.withTransaction {
            database.recurrenceRuleDao().insert(entity)
            materialize(entity, rule.startDate, ZoneId.systemDefault())
        }
        return entity.toDomain()
    }

    override suspend fun materializeDue(through: Instant, zoneId: ZoneId) {
        val rules = database.recurrenceRuleDao().getActive(through.toEpochMilli())
        rules.forEach { rule ->
            database.withTransaction { materialize(rule, through, zoneId) }
        }
    }

    private suspend fun materialize(rule: RecurrenceRuleEntity, through: Instant, zoneId: ZoneId) {
        val dates = RecurrenceOccurrenceCalculator.occurrences(
            frequency = RecurrenceFrequency.fromStorage(rule.frequency),
            interval = rule.interval,
            startDate = Instant.ofEpochMilli(rule.startDateEpochMillis),
            endDate = rule.endDateEpochMillis?.let(Instant::ofEpochMilli),
            since = rule.lastMaterializedDateEpochMillis?.let(Instant::ofEpochMilli),
            through = through,
            zoneId = zoneId,
        )
        if (dates.isEmpty()) return
        database.transactionDao().insertAll(dates.map { occurrence ->
            TransactionEntity(
                id = UUID.nameUUIDFromBytes("${rule.id}:${occurrence.toEpochMilli()}".toByteArray(StandardCharsets.UTF_8)).toString(),
                timestampEpochMillis = occurrence.toEpochMilli(),
                amountDecimal = rule.amountDecimal,
                note = rule.note,
                categoryLabel = rule.categoryLabel,
                categoryId = rule.categoryId,
                currencyCode = rule.currencyCode,
                goalId = rule.goalId,
                recurrenceRuleId = rule.id,
            )
        })
        database.recurrenceRuleDao().updateLastMaterializedDate(rule.id, dates.last().toEpochMilli())
    }
}

private fun NewRecurrenceRule.toEntity() = RecurrenceRuleEntity(
    id = UUID.randomUUID().toString(),
    frequency = frequency.storageValue,
    interval = interval,
    startDateEpochMillis = startDate.toEpochMilli(),
    endDateEpochMillis = null,
    lastMaterializedDateEpochMillis = null,
    amountDecimal = MoneyCodec.encode(amount),
    note = note,
    categoryLabel = categoryLabel,
    categoryId = categoryId,
    currencyCode = currencyCode,
    goalId = goalId,
)

private fun RecurrenceRuleEntity.toDomain() = RecurrenceRule(
    id = id,
    frequency = RecurrenceFrequency.fromStorage(frequency),
    interval = interval,
    startDate = Instant.ofEpochMilli(startDateEpochMillis),
    endDate = endDateEpochMillis?.let(Instant::ofEpochMilli),
    lastMaterializedDate = lastMaterializedDateEpochMillis?.let(Instant::ofEpochMilli),
    amount = MoneyCodec.decode(amountDecimal),
    note = note,
    categoryLabel = categoryLabel,
    categoryId = categoryId,
    currencyCode = currencyCode,
    goalId = goalId,
)

private val RecurrenceFrequency.storageValue: String get() = name.lowercase()

private fun RecurrenceFrequency.Companion.fromStorage(value: String) = when (value) {
    "weekly" -> RecurrenceFrequency.WEEKLY
    "monthly" -> RecurrenceFrequency.MONTHLY
    "yearly" -> RecurrenceFrequency.YEARLY
    else -> error("Unknown recurrence frequency: $value")
}
