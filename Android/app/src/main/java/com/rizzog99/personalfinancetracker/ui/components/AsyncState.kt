package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.rizzog99.personalfinancetracker.R

@Composable
fun LoadingState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().semantics { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator()
        Text(stringResource(R.string.loading), modifier = Modifier.padding(top = 16.dp))
    }
}

@Composable
fun EmptyState(
    title: String = stringResource(R.string.empty_state_title),
    message: String = stringResource(R.string.empty_state_message),
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
        Text(message, modifier = Modifier.padding(top = 8.dp))
    }
}

/**
 * Shown in place of the whole app when stored data could not be opened (#130, #131).
 *
 * The screen exists to replace two much worse answers: a database silently deleted and presented
 * as a brand-new account, and settings silently rendered at their defaults. So the copy's job is
 * to say what could not be opened and — the part that matters to someone whose finances just
 * vanished — that nothing was deleted.
 *
 * ponytail: no retry button. A retry that helps would have to close and rebuild the Room instance
 * and every repository already holding it; a button that re-renders the same screen is worse than
 * none. Relaunching is the retry, and it genuinely re-attempts the open. If in-app recovery is
 * wanted later, restoring from a backup (#87) is the action to put here, not "try again".
 */
@Composable
fun StoredDataUnavailableState(
    message: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp)
            .semantics { liveRegion = LiveRegionMode.Assertive },
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = stringResource(R.string.stored_data_unavailable_title),
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            text = stringResource(R.string.stored_data_unavailable_reassurance),
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 16.dp),
        )
    }
}

@Composable
fun ErrorState(
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = stringResource(R.string.error_state_title),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.semantics { heading() },
        )
        Button(onClick = onRetry, modifier = Modifier.padding(top = 16.dp)) {
            Text(stringResource(R.string.retry))
        }
    }
}
