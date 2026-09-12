package com.rizzog99.personalfinancetracker.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.rizzog99.personalfinancetracker.R

// Roboto Flex (bundled variable font, res/font/roboto_flex.ttf) for
// display/headline/title, matching the design. Roboto is Android's system
// default and needs no bundling for body/label.
@OptIn(ExperimentalTextApi::class)
private val RobotoFlex = FontFamily(
    Font(
        R.font.roboto_flex,
        weight = FontWeight.Normal,
        variationSettings = FontVariation.Settings(FontVariation.weight(400)),
    ),
    Font(
        R.font.roboto_flex,
        weight = FontWeight.Medium,
        variationSettings = FontVariation.Settings(FontVariation.weight(500)),
    ),
    Font(
        R.font.roboto_flex,
        weight = FontWeight.Bold,
        variationSettings = FontVariation.Settings(FontVariation.weight(700)),
    ),
)

private val Roboto = FontFamily.Default

val PersonalFinanceTypography = Typography(
    displayLarge = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 45.sp, lineHeight = 52.sp),
    displayMedium = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 36.sp, lineHeight = 44.sp),
    displaySmall = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 28.sp, lineHeight = 32.sp),
    headlineLarge = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 28.sp, lineHeight = 32.sp),
    headlineMedium = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 24.sp, lineHeight = 30.sp),
    headlineSmall = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 22.sp, lineHeight = 28.sp),
    titleLarge = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Normal, fontSize = 20.sp, lineHeight = 28.sp),
    titleMedium = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Medium, fontSize = 16.sp, lineHeight = 24.sp),
    titleSmall = TextStyle(fontFamily = RobotoFlex, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    bodyLarge = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Normal, fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    labelMedium = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
    labelSmall = TextStyle(fontFamily = Roboto, fontWeight = FontWeight.Medium, fontSize = 11.sp, lineHeight = 14.sp),
)
