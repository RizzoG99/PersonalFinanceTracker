package com.rizzog99.personalfinancetracker.data.repository

import com.rizzog99.personalfinancetracker.data.local.DailyForecastCacheEntity
import com.rizzog99.personalfinancetracker.data.local.HealthScoreSnapshotEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.insight.DailyForecastCache
import com.rizzog99.personalfinancetracker.domain.insight.DayValue
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import java.time.Instant
import org.json.JSONArray

/**
 * Persistence for the two derived-but-durable Insights records. Health-score and forecast
 * *calculations* stay in pure domain services; this only stores and returns what they produced.
 */
interface InsightRepository {
    /** Newest first, matching the frozen reverse `timestamp` sort with a fetch limit. */
    suspend fun recentSnapshots(limit: Int): List<HealthScoreSnapshot>

    /** Appends a snapshot, as the frozen `saveSnapshot` does. Re-saving an id replaces that row. */
    suspend fun saveSnapshot(snapshot: HealthScoreSnapshot): HealthScoreSnapshot

    /** `null` when nothing has been cached yet. */
    suspend fun forecastCache(): DailyForecastCache?

    /** Replaces any previously cached month — the cache holds exactly one row or none. */
    suspend fun saveForecastCache(cache: DailyForecastCache)

    suspend fun clearForecastCache()
}

class RoomInsightRepository(
    private val database: PersonalFinanceDatabase,
) : InsightRepository {
    private val snapshotDao = database.healthScoreSnapshotDao()
    private val forecastDao = database.dailyForecastCacheDao()

    override suspend fun recentSnapshots(limit: Int): List<HealthScoreSnapshot> {
        require(limit > 0) { "A snapshot limit must be greater than zero." }
        return snapshotDao.recent(limit).map(HealthScoreSnapshotEntity::toDomain)
    }

    override suspend fun saveSnapshot(snapshot: HealthScoreSnapshot): HealthScoreSnapshot =
        snapshot.toEntity().also { snapshotDao.upsert(it) }.toDomain()

    override suspend fun forecastCache(): DailyForecastCache? =
        forecastDao.get()?.toDomain()

    override suspend fun saveForecastCache(cache: DailyForecastCache) {
        forecastDao.upsert(cache.toEntity())
    }

    override suspend fun clearForecastCache() {
        forecastDao.clear()
    }
}

private fun HealthScoreSnapshot.toEntity() = HealthScoreSnapshotEntity(
    id = id,
    timestampEpochMillis = timestamp.toEpochMilli(),
    score = score,
    savingsScore = savingsScore,
    stabilityScore = stabilityScore,
    adherenceScore = adherenceScore,
    subscriptionScore = subscriptionScore,
)

private fun HealthScoreSnapshotEntity.toDomain() = HealthScoreSnapshot(
    id = id,
    timestamp = Instant.ofEpochMilli(timestampEpochMillis),
    score = score,
    savingsScore = savingsScore,
    stabilityScore = stabilityScore,
    adherenceScore = adherenceScore,
    subscriptionScore = subscriptionScore,
)

private fun DailyForecastCache.toEntity(): DailyForecastCacheEntity {
    require(monthKey.isNotBlank()) { "A forecast cache needs a month key." }
    return DailyForecastCacheEntity(
        monthKey = monthKey,
        computedUpToDay = computedUpToDay,
        dayValuesJson = encodeDayValues(dayValues),
    )
}

private fun DailyForecastCacheEntity.toDomain() = DailyForecastCache(
    monthKey = monthKey,
    computedUpToDay = computedUpToDay,
    dayValues = decodeDayValues(dayValuesJson),
)

/**
 * `[[day, "amount"], ...]` — a JSON array keeps day order stable, and the amount stays a decimal
 * string so the round trip is exact. The frozen iOS cache uses `[Double]`; money never becomes a
 * binary float on this side.
 */
private fun encodeDayValues(values: List<DayValue>): String {
    val array = JSONArray()
    for (value in values) {
        array.put(JSONArray().put(value.day).put(MoneyCodec.encode(value.amount)))
    }
    return array.toString()
}

private fun decodeDayValues(encoded: String): List<DayValue> {
    if (encoded.isBlank()) return emptyList()
    val array = JSONArray(encoded)
    return (0 until array.length()).map { index ->
        val pair = array.getJSONArray(index)
        DayValue(day = pair.getInt(0), amount = MoneyCodec.decode(pair.getString(1)))
    }
}
