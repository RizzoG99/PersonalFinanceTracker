package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Backpack
import androidx.compose.material.icons.outlined.BeachAccess
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.Flight
import androidx.compose.material.icons.outlined.Landscape
import androidx.compose.material.icons.outlined.LocationCity
import androidx.compose.material.icons.outlined.Sailing
import androidx.compose.material.icons.outlined.Tram
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The Material counterpart of a travel's iOS SF Symbol (#284, D-05). The symbol name is what is
 * stored, so data stays portable; anything unknown draws as a plane, iOS's default.
 */
fun travelIcon(symbolName: String): ImageVector = when (symbolName) {
    "beach.umbrella" -> Icons.Outlined.BeachAccess
    "mountain.2" -> Icons.Outlined.Landscape
    "building.2" -> Icons.Outlined.LocationCity
    "car" -> Icons.Outlined.DirectionsCar
    "tram" -> Icons.Outlined.Tram
    "sailboat" -> Icons.Outlined.Sailing
    "backpack" -> Icons.Outlined.Backpack
    else -> Icons.Outlined.Flight
}

/** What TalkBack calls each icon choice in the travel form; never the raw symbol name. */
@androidx.annotation.StringRes
fun travelIconLabel(symbolName: String): Int = when (symbolName) {
    "beach.umbrella" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_beach
    "mountain.2" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_mountain
    "building.2" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_city
    "car" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_car
    "tram" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_tram
    "sailboat" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_sailboat
    "backpack" -> com.rizzog99.personalfinancetracker.R.string.travel_icon_backpack
    else -> com.rizzog99.personalfinancetracker.R.string.travel_icon_airplane
}
