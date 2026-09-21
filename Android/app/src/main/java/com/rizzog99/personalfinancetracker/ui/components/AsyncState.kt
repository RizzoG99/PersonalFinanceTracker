package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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

/**
 * Work is in progress and nothing is known yet (#111 AC-01).
 *
 * The live region sits on the **label**, not on the surrounding column. On the column it announced
 * nothing — the column carries no text of its own — while still being a region TalkBack watches for
 * change. On the label it announces the words once, when the label enters the tree, and stays
 * silent through the recompositions the spinner's animation causes, because the string never
 * changes. Indeterminate progress semantics come from `CircularProgressIndicator` itself.
 *
 * The caller owns the height: [LoadingState] fills its width and wraps, so Home and Insights pass
 * `fillMaxSize()` to centre it in a whole screen while Activity drops it into a list item.
 */
@Composable
fun LoadingState(
    modifier: Modifier = Modifier,
    message: String = stringResource(R.string.loading),
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator()
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(top = 16.dp)
                .semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
}

/**
 * There is genuinely nothing to show (#111 AC-02, AC-03).
 *
 * [title] and [message] are required rather than defaulted: a first-run ledger and a filter that
 * matched nothing are different states with different copy, and a shared default is how the two
 * quietly become one. [action] is a slot so each caller keeps its own verb and its own button
 * emphasis — "Add transaction" and "Clear search and filters" are not interchangeable.
 *
 * This composable holds no state. Whether the ledger is empty, or merely filtered to nothing, is
 * decided in the ViewModel and passed here already resolved.
 */
@Composable
fun EmptyState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    action: (@Composable () -> Unit)? = null,
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
        )
        action?.invoke()
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

/**
 * Something failed and trying again can plausibly fix it (#111 AC-04, AC-05).
 *
 * [message] is required. A title alone ("Something went wrong") names that a failure happened but
 * not what the user lost or kept, and this screen's whole job is to be the alternative to a lie —
 * a spinner that never resolves, or an empty ledger that isn't empty.
 *
 * [message] is a caller-supplied string, which is the point: it comes from a string resource, never
 * from `Throwable.message`. Frozen iOS draws the same line in
 * `EditAddTransactionView` — "Not `error.localizedDescription`: a capture failure is a raw
 * AVFoundationErrorDomain code … that means nothing to a user reading it."
 *
 * Stateless by construction. Re-entering the error state after a failed retry, and not running two
 * retries at once, are the ViewModel's job — this composable only reports the tap.
 */
@Composable
fun ErrorState(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
    title: String = stringResource(R.string.error_state_title),
) {
    Column(
        modifier = modifier.fillMaxWidth().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
        Button(onClick = onRetry) { Text(stringResource(R.string.retry)) }
    }
}
