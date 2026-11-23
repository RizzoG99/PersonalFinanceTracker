package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material.icons.outlined.Star
import org.junit.Assert.assertEquals
import org.junit.Test

/** #291 AC-03: an icon token picks its own icon, never one whose name merely contains a substring of it. */
class CategoryIconTokenTest {
    @Test
    fun ac03_iconTokensMatchExactly() {
        val expected = mapOf(
            "creditcard.fill" to Icons.Outlined.CreditCard, // "car" used to win here
            "creditcard" to Icons.Outlined.CreditCard,
            "car" to Icons.Outlined.DirectionsCar,
            "cart" to Icons.Outlined.ShoppingCart,
            "takeoutbag.and.cup.and.straw" to Icons.Outlined.Restaurant,
            "star.circle" to Icons.Outlined.Star,
            "chart.line.uptrend.xyaxis" to Icons.AutoMirrored.Outlined.ShowChart,
            "unknown.token" to Icons.Outlined.Category,
        )
        expected.forEach { (token, icon) -> assertEquals(token, icon.name, categoryIconFor(token).name) }
    }
}
