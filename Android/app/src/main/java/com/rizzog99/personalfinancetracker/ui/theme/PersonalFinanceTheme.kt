package com.rizzog99.personalfinancetracker.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.isSystemInDarkTheme

data class FinancePalette(
    val positive: Color,
    val negative: Color,
    val textMid: Color,
    val textDim: Color,
    val surfaceRaised: Color,
    val hairline: Color,
    val topBloom: Color,
    val bottomBloom: Color,
    val centreBloom: Color,
)

val LocalFinancePalette = staticCompositionLocalOf<FinancePalette> {
    error("Finance palette was not provided.")
}

private val LightColors = lightColorScheme(
    primary = Color(0xFF4F46E5),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE5E4FF),
    onPrimaryContainer = Color(0xFF241B78),
    secondary = Color(0xFF246B58),
    onSecondary = Color.White,
    background = Color(0xFFDCE0EE),
    onBackground = Color(0xFF0F172A),
    surface = Color(0xFFF9FAFF),
    onSurface = Color(0xFF0F172A),
    surfaceVariant = Color(0xFFE8EAF3),
    onSurfaceVariant = Color(0xFF4B5563),
    outline = Color(0xFF747B8D),
    error = Color(0xFF991B1B),
    onError = Color.White,
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFA1A3FF),
    onPrimary = Color(0xFF28206F),
    primaryContainer = Color(0xFF4641B9),
    onPrimaryContainer = Color(0xFFE5E4FF),
    secondary = Color(0xFF7CE2C0),
    onSecondary = Color(0xFF073C30),
    background = Color(0xFF120704),
    onBackground = Color(0xFFF9F5F1),
    surface = Color(0xFF1B100D),
    onSurface = Color(0xFFF9F5F1),
    surfaceVariant = Color(0xFF2B1C17),
    onSurfaceVariant = Color(0xFFD8C4BC),
    outline = Color(0xFF9D8580),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
)

private val LightPalette = FinancePalette(
    positive = Color(0xFF0A6B4F),
    negative = Color(0xFF991B1B),
    textMid = Color(0xFF4B5563),
    textDim = Color(0xFF6B7280),
    surfaceRaised = Color(0xE6FFFFFF),
    hairline = Color(0x260F172A),
    topBloom = Color(0xFFEEF0FF),
    bottomBloom = Color(0xFFEAF7F3),
    centreBloom = Color(0xFFEEF0FF),
)

private val DarkPalette = FinancePalette(
    positive = Color(0xFF9FD3A0),
    negative = Color(0xFFFFB4AB),
    textMid = Color(0xFFD8C4BC),
    textDim = Color(0xFFB9A39C),
    surfaceRaised = Color(0x12FFFFFF),
    hairline = Color(0x1FFFFFFF),
    topBloom = Color(0x38636BFF),
    bottomBloom = Color(0x1A22D3A0),
    centreBloom = Color(0x1A6366F1),
)

@Composable
fun PersonalFinanceTheme(content: @Composable () -> Unit) {
    val darkTheme = isSystemInDarkTheme()
    CompositionLocalProvider(LocalFinancePalette provides if (darkTheme) DarkPalette else LightPalette) {
        MaterialTheme(
            colorScheme = if (darkTheme) DarkColors else LightColors,
            typography = Typography(),
            content = content,
        )
    }
}
