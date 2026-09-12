package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.foundation.background
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
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.ui.theme.CardShape

/**
 * The app's root surface. The design uses a flat Material 3 surface, not the
 * gradient/bloom background the iOS port carried over — kept as a named
 * wrapper only because sheet content ([InsightsScreen], [ActivityScreen])
 * still nests it for a consistent sheet body background.
 */
@Composable
fun AppBackground(modifier: Modifier = Modifier.fillMaxSize(), content: @Composable () -> Unit) {
    Box(modifier = modifier.background(MaterialTheme.colorScheme.surface)) {
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            content()
        }
    }
}

/** A visual drag affordance for modal bottom sheets. */
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
                .width(32.dp)
                .height(4.dp)
                .background(MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(2.dp)),
        )
    }
}

/** The app's primary grouped-content card: surfaceContainer, 20dp radius, no border. */
@Composable
fun FinanceCard(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Card(
        modifier = modifier,
        shape = CardShape,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        content()
    }
}
