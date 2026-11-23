package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.BusinessCenter
import androidx.compose.material.icons.outlined.Build
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.Checkroom
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.DirectionsBus
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.LocalDining
import androidx.compose.material.icons.outlined.LocalGasStation
import androidx.compose.material.icons.outlined.LocalHospital
import androidx.compose.material.icons.outlined.LocalTaxi
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Pets
import androidx.compose.material.icons.outlined.PhoneIphone
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.outlined.Work
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material.icons.outlined.Home
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Picks by the symbol's first component ("creditcard" in "creditcard.fill"), exactly: matching
 * substrings gave `creditcard.fill` the car icon because "car" was checked first (#291).
 */
fun categoryIconFor(token: String): ImageVector = when (token.substringBefore('.')) {
    "cart" -> Icons.Outlined.ShoppingCart
    "fork", "cup", "takeoutbag" -> Icons.Outlined.Restaurant
    "house" -> Icons.Outlined.Home
    "briefcase" -> Icons.Outlined.BusinessCenter
    "banknote" -> Icons.Outlined.AccountBalanceWallet
    "chart" -> Icons.AutoMirrored.Outlined.ShowChart
    "gift" -> Icons.Outlined.CardGiftcard
    "airplane" -> Icons.Outlined.Flight
    "fuelpump" -> Icons.Outlined.LocalGasStation
    "wrench", "bolt" -> Icons.Outlined.Build
    "bus" -> Icons.Outlined.DirectionsBus
    "taxi" -> Icons.Outlined.LocalTaxi
    "car" -> Icons.Outlined.DirectionsCar
    "star" -> Icons.Outlined.Star
    "trophy" -> Icons.Outlined.EmojiEvents
    "iphone" -> Icons.Outlined.PhoneIphone
    "globe" -> Icons.Outlined.Public
    "tv" -> Icons.Outlined.Tv
    "tshirt" -> Icons.Outlined.Checkroom
    "bag" -> Icons.Outlined.ShoppingBag
    "gamecontroller" -> Icons.Outlined.SportsEsports
    "book" -> Icons.AutoMirrored.Outlined.MenuBook
    "cross", "pills", "dumbbell" -> Icons.Outlined.LocalHospital
    "film" -> Icons.Outlined.Movie
    "music" -> Icons.Outlined.MusicNote
    "graduationcap" -> Icons.Outlined.School
    "pawprint" -> Icons.Outlined.Pets
    "arrow" -> Icons.AutoMirrored.Outlined.Undo
    "creditcard" -> Icons.Outlined.CreditCard
    "ellipsis" -> Icons.Outlined.MoreHoriz
    "dining" -> Icons.Outlined.LocalDining
    "work" -> Icons.Outlined.Work
    else -> Icons.Outlined.Category
}
