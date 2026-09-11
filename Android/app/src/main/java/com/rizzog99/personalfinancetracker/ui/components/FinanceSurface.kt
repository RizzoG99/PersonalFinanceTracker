package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import kotlin.math.max

@Composable
fun AppBackground(modifier: Modifier = Modifier.fillMaxSize(), content: @Composable () -> Unit) {
    val palette = LocalFinancePalette.current
    Box(
        modifier = modifier
            .background(MaterialTheme.colorScheme.background)
            .drawWithCache {
                val radius = max(size.width, size.height) * 0.72f
                val topLeft = Brush.radialGradient(
                    colors = listOf(palette.topBloom, Color.Transparent),
                    center = Offset(size.width * 0.2f, 0f),
                    radius = radius,
                )
                val bottomRight = Brush.radialGradient(
                    colors = listOf(palette.bottomBloom, Color.Transparent),
                    center = Offset(size.width * 0.8f, size.height),
                    radius = radius,
                )
                val centre = Brush.radialGradient(
                    colors = listOf(palette.centreBloom, Color.Transparent),
                    center = Offset(size.width / 2f, size.height / 2f),
                    radius = radius,
                )
                onDrawBehind {
                    drawRect(topLeft)
                    drawRect(bottomRight)
                    drawRect(centre)
                }
            },
    ) {
        // AppBackground is the top-level surface. Provide the semantic foreground explicitly:
        // a Box alone would otherwise inherit the platform window's (light-theme) black text
        // colour when the system changes to dark appearance.
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onBackground) {
            content()
        }
    }
}

/** A visual drag affordance that stays within the app-gradient sheet surface. */
@Composable
fun SheetDragHandle() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp, bottom = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .width(36.dp)
                .height(4.dp)
                .background(LocalFinancePalette.current.textDim.copy(alpha = 0.6f), RoundedCornerShape(2.dp)),
        )
    }
}

@Composable
fun FinanceCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val palette = LocalFinancePalette.current
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = palette.surfaceRaised),
        border = BorderStroke(1.dp, palette.hairline),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        content()
    }
}
