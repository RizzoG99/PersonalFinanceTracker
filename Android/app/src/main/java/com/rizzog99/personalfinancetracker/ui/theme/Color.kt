package com.rizzog99.personalfinancetracker.ui.theme

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

// Transcribed 1:1 from the Material 3 design's [data-m3] tonal palette
// (Claude Design project "Personal Finance Tracker Design System",
// Android Material 3.dc.html). Brand-locked indigo, no dynamic color.

internal val LightColorScheme = lightColorScheme(
    primary = Color(0xFF4F46E5),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE2DFFF),
    onPrimaryContainer = Color(0xFF120079),
    secondary = Color(0xFF4F46E5),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFE2DFFF),
    onSecondaryContainer = Color(0xFF120079),
    tertiary = Color(0xFF0E7490),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFCFF4FF),
    onTertiaryContainer = Color(0xFF001F27),
    background = Color(0xFFFCF8FF),
    onBackground = Color(0xFF1B1B21),
    surface = Color(0xFFFCF8FF),
    onSurface = Color(0xFF1B1B21),
    surfaceVariant = Color(0xFFE4E1E9),
    onSurfaceVariant = Color(0xFF46464F),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF6F2FA),
    surfaceContainer = Color(0xFFF0EDF4),
    surfaceContainerHigh = Color(0xFFEAE7EF),
    surfaceContainerHighest = Color(0xFFE4E1E9),
    outline = Color(0xFF77767F),
    outlineVariant = Color(0xFFC7C5D0),
    error = Color(0xFF991B1B),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFBDDDD),
    onErrorContainer = Color(0xFF410002),
    scrim = Color(0x52000000),
    inverseSurface = Color(0xFF303036),
    inverseOnSurface = Color(0xFFF3EFF7),
    inversePrimary = Color(0xFFC3C0FF),
)

internal val DarkColorScheme = darkColorScheme(
    primary = Color(0xFFC3C0FF),
    onPrimary = Color(0xFF241A9A),
    primaryContainer = Color(0xFF3B32BD),
    onPrimaryContainer = Color(0xFFE2DFFF),
    secondary = Color(0xFFC3C0FF),
    onSecondary = Color(0xFF241A9A),
    secondaryContainer = Color(0xFF3B32BD),
    onSecondaryContainer = Color(0xFFE2DFFF),
    tertiary = Color(0xFF14B8A6),
    onTertiary = Color(0xFF00332C),
    tertiaryContainer = Color(0xFF004A40),
    onTertiaryContainer = Color(0xFFCFF4FF),
    background = Color(0xFF131318),
    onBackground = Color(0xFFE5E1E9),
    surface = Color(0xFF131318),
    onSurface = Color(0xFFE5E1E9),
    surfaceVariant = Color(0xFF35343B),
    onSurfaceVariant = Color(0xFFC7C5D0),
    surfaceContainerLowest = Color(0xFF0D0D12),
    surfaceContainerLow = Color(0xFF1B1B21),
    surfaceContainer = Color(0xFF1F1F25),
    surfaceContainerHigh = Color(0xFF2A2930),
    surfaceContainerHighest = Color(0xFF35343B),
    outline = Color(0xFF918F9A),
    outlineVariant = Color(0xFF46464F),
    error = Color(0xFFF87171),
    onError = Color(0xFF4D1F1F),
    errorContainer = Color(0xFF4D1F1F),
    onErrorContainer = Color(0xFFFBDDDD),
    scrim = Color(0x80000000),
    inverseSurface = Color(0xFFE5E1E9),
    inverseOnSurface = Color(0xFF303036),
    inversePrimary = Color(0xFF4F46E5),
)

/**
 * Money and category colors that are not part of the Material role system:
 * money direction is "income/expense", not "success/error", and the 7
 * category colors are user-assignable rather than semantic roles.
 */
data class FinanceExtendedColors(
    val positive: Color,
    val negative: Color,
    val positiveContainer: Color,
    val negativeContainer: Color,
    val categoryIndigo: Color,
    val categoryGreen: Color,
    val categoryAmber: Color,
    val categoryPink: Color,
    val categoryPurple: Color,
    val categoryTeal: Color,
    val categoryGray: Color,
)

internal val LightExtendedColors = FinanceExtendedColors(
    positive = Color(0xFF0A6B4F),
    negative = Color(0xFF991B1B),
    positiveContainer = Color(0xFFD3F1E4),
    negativeContainer = Color(0xFFFBDDDD),
    categoryIndigo = Color(0xFF4F46E5),
    categoryGreen = Color(0xFF0A6B4F),
    categoryAmber = Color(0xFFB45309),
    categoryPink = Color(0xFFDB2777),
    categoryPurple = Color(0xFF7C3AED),
    categoryTeal = Color(0xFF0E7490),
    categoryGray = Color(0xFF64748B),
)

internal val DarkExtendedColors = FinanceExtendedColors(
    positive = Color(0xFF22D3A0),
    negative = Color(0xFFF87171),
    positiveContainer = Color(0xFF0D3F31),
    negativeContainer = Color(0xFF4D1F1F),
    categoryIndigo = Color(0xFF6366F1),
    categoryGreen = Color(0xFF22D3A0),
    categoryAmber = Color(0xFFF59E0B),
    categoryPink = Color(0xFFEC4899),
    categoryPurple = Color(0xFF8B5CF6),
    categoryTeal = Color(0xFF14B8A6),
    categoryGray = Color(0xFF94A3B8),
)
