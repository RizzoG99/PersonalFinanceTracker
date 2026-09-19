package com.rizzog99.personalfinancetracker.data.repository

import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.CreditCardDao
import com.rizzog99.personalfinancetracker.data.local.CreditCardEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.credit.CreditCard
import com.rizzog99.personalfinancetracker.domain.credit.NewCreditCard
import com.rizzog99.personalfinancetracker.domain.money.MoneyCodec
import java.math.BigDecimal
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

interface CreditCardRepository {
    /** Sorted by name, matching the frozen `CreditCardRepository.fetchAll()`. */
    fun observeAll(): Flow<List<CreditCard>>
    suspend fun get(id: String): CreditCard?
    suspend fun add(card: NewCreditCard): CreditCard
    suspend fun update(card: CreditCard): CreditCard

    /** Credit cards own no relationships, so this removes exactly one row and nothing else. */
    suspend fun delete(id: String)
}

class RoomCreditCardRepository(
    private val database: PersonalFinanceDatabase,
) : CreditCardRepository {
    private val dao: CreditCardDao = database.creditCardDao()

    override fun observeAll(): Flow<List<CreditCard>> = dao.observeAll().map { entities ->
        entities.map(CreditCardEntity::toDomain)
    }

    override suspend fun get(id: String): CreditCard? = dao.get(id)?.toDomain()

    override suspend fun add(card: NewCreditCard): CreditCard = database.withTransaction {
        card.toEntity().also { dao.insert(it) }.toDomain()
    }

    override suspend fun update(card: CreditCard): CreditCard = database.withTransaction {
        card.toEntity().also { dao.update(it) }.toDomain()
    }

    override suspend fun delete(id: String) {
        dao.delete(id)
    }
}

private fun validated(name: String, lastFour: String, balance: BigDecimal, limit: BigDecimal): String {
    val trimmedName = name.trim()
    require(trimmedName.isNotEmpty()) { "A credit card name cannot be blank." }
    require(lastFour.length <= 4 && lastFour.all(Char::isDigit)) {
        "A credit card's last four digits must be at most four digits."
    }
    require(balance >= BigDecimal.ZERO) { "A credit card balance cannot be negative." }
    require(limit >= BigDecimal.ZERO) { "A credit card limit cannot be negative." }
    return trimmedName
}

private fun NewCreditCard.toEntity() = CreditCardEntity(
    id = UUID.randomUUID().toString(),
    name = validated(name, lastFour, balance, limit),
    lastFour = lastFour,
    balanceDecimal = MoneyCodec.encode(balance),
    limitDecimal = MoneyCodec.encode(limit),
    colorToken = colorToken,
    currencyCode = currencyCode,
)

private fun CreditCard.toEntity() = CreditCardEntity(
    id = id,
    name = validated(name, lastFour, balance, limit),
    lastFour = lastFour,
    balanceDecimal = MoneyCodec.encode(balance),
    limitDecimal = MoneyCodec.encode(limit),
    colorToken = colorToken,
    currencyCode = currencyCode,
)

private fun CreditCardEntity.toDomain() = CreditCard(
    id = id,
    name = name,
    lastFour = lastFour,
    balance = MoneyCodec.decode(balanceDecimal),
    limit = MoneyCodec.decode(limitDecimal),
    colorToken = colorToken,
    currencyCode = currencyCode,
)
