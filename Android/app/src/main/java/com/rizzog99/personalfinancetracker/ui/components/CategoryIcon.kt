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

fun categoryIconFor(token: String): ImageVector = when {
    token.contains("cart") -> Icons.Outlined.ShoppingCart
    token.contains("fork") || token.contains("cup") || token.contains("takeout") -> Icons.Outlined.Restaurant
    token.contains("house") -> Icons.Outlined.Home
    token.contains("briefcase") -> Icons.Outlined.BusinessCenter
    token.contains("banknote") -> Icons.Outlined.AccountBalanceWallet
    token.contains("chart") -> Icons.AutoMirrored.Outlined.ShowChart
    token.contains("gift") -> Icons.Outlined.CardGiftcard
    token.contains("airplane") -> Icons.Outlined.Flight
    token.contains("fuel") -> Icons.Outlined.LocalGasStation
    token.contains("wrench") || token.contains("bolt") -> Icons.Outlined.Build
    token.contains("bus") -> Icons.Outlined.DirectionsBus
    token.contains("taxi") -> Icons.Outlined.LocalTaxi
    token.contains("car") -> Icons.Outlined.DirectionsCar
    token.contains("star") -> Icons.Outlined.Star
    token.contains("trophy") -> Icons.Outlined.EmojiEvents
    token.contains("iphone") -> Icons.Outlined.PhoneIphone
    token.contains("globe") -> Icons.Outlined.Public
    token.contains("tv") -> Icons.Outlined.Tv
    token.contains("tshirt") -> Icons.Outlined.Checkroom
    token.contains("bag") -> Icons.Outlined.ShoppingBag
    token.contains("gamecontroller") -> Icons.Outlined.SportsEsports
    token.contains("book") -> Icons.AutoMirrored.Outlined.MenuBook
    token.contains("cross") || token.contains("pills") || token.contains("dumbbell") -> Icons.Outlined.LocalHospital
    token.contains("film") -> Icons.Outlined.Movie
    token.contains("music") -> Icons.Outlined.MusicNote
    token.contains("graduationcap") -> Icons.Outlined.School
    token.contains("pawprint") -> Icons.Outlined.Pets
    token.contains("arrow.uturn") -> Icons.AutoMirrored.Outlined.Undo
    token.contains("creditcard") -> Icons.Outlined.CreditCard
    token.contains("ellipsis") -> Icons.Outlined.MoreHoriz
    token.contains("dining") -> Icons.Outlined.LocalDining
    token.contains("work") -> Icons.Outlined.Work
    else -> Icons.Outlined.Category
}
