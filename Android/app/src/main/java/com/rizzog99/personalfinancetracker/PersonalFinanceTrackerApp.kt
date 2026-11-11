package com.rizzog99.personalfinancetracker

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import com.rizzog99.personalfinancetracker.ui.components.LocalAppObscured
import com.rizzog99.personalfinancetracker.ui.components.LocalTextFocusReleasers
import com.rizzog99.personalfinancetracker.ui.components.ReleaseTextFocusWhileObscured
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.data.local.StartupFailure
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.features.security.AppLockSession
import com.rizzog99.personalfinancetracker.features.security.LockState
import com.rizzog99.personalfinancetracker.features.security.PinUnlockScreen
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.components.LoadingState
import com.rizzog99.personalfinancetracker.ui.components.StoredDataUnavailableState
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode

@Composable
fun PersonalFinanceTrackerApp() {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val themeMode by application.preferencesRepository.themeMode.collectAsState(initial = ThemeMode.SYSTEM)
    val pinLock by application.pinLockRepository.state.collectAsState()
    val biometricEnabled by application.preferencesRepository.biometricEnabled.collectAsState(initial = false)
    val session: AppLockSession = viewModel()
    // Snapshot state, read directly: no frame of lag between the activity writing it and the
    // windows below seeing it (see AppLockSession).
    val lockState = session.state
    val privacyCover = session.privacyCover

    val startupFailure by application.startupFailure.collectAsState()
    val databaseProbed by application.databaseProbed.collectAsState()

    PersonalFinanceTheme(themeMode = themeMode) {
        // Nothing below may compose until the store has been opened once off the main thread.
        // Otherwise a screen collecting a Room flow opens it here instead, and an unopenable store
        // takes the process down as `FATAL EXCEPTION: main` before the branch below ever runs.
        if (!databaseProbed && startupFailure == null) {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                FoundationStartupLoadingState(
                    message = stringResource(R.string.startup_loading_data),
                )
            }
            return@PersonalFinanceTheme
        }
        // Ahead of the lock: a store the app cannot read is not something a PIN prompt improves,
        // and this state shows no financial data of any kind (#130, #131).
        if (startupFailure != null) {
            Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                StoredDataUnavailableState(
                    message = stringResource(
                        when (startupFailure) {
                            StartupFailure.PREFERENCES -> R.string.stored_data_unavailable_preferences
                            else -> R.string.stored_data_unavailable_database
                        },
                    ),
                )
            }
            return@PersonalFinanceTheme
        }
        // Past the cold gate the shell below has exactly *one* call site and stays composed, relocks
        // included (#319). Two would not do: `pinLock` is a flow, not a launch-time
        // snapshot, so saving a PIN from Settings flips it to `Set` mid-session, and a
        // `PersonalFinanceNavHost()` in a second `when` branch is a different composition group —
        // the shell would be torn down and rebuilt at Home, losing the destination the user was on
        // (#132). Frozen iOS keeps its shell mounted across the whole lock cycle for the same
        // reason.
        val lock = pinLock
        when {
            // Reading the secret means a file read plus a Keystore decrypt. Hold on the plain app
            // background until that answers, rather than flashing the dashboard at someone the
            // lock screen is about to stop.
            lockState == LockState.COLD && lock is PinLock.Unknown ->
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                    FoundationStartupLoadingState(
                        message = stringResource(R.string.startup_loading_security),
                    )
                }
            lockState == LockState.COLD && lock is PinLock.Set -> PinUnlockScreen(
                expectedHash = lock.secret.hash,
                expectedSalt = lock.secret.salt,
                biometricEnabled = biometricEnabled,
                onUnlocked = session::unlock,
            )
            else -> {
                // No PIN means nothing to unlock into; a relocked session waits for the PIN.
                SideEffect { if (lock !is PinLock.Set) session.unlock() }
                val relocked = lockState == LockState.RELOCKED && lock is PinLock.Set
                val cover = MaterialTheme.colorScheme.surface
                // Every window below (sheets, dialogs) inherits this and drops its text focus.
                val obscured = remember(session) {
                    { session.away || session.privacyCover || session.state == LockState.RELOCKED }
                }
                CompositionLocalProvider(
                    LocalAppObscured provides obscured,
                    LocalTextFocusReleasers provides session.textFocus,
                ) {
                    ReleaseTextFocusWhileObscured()
                    // The wrapper is always there, so the NavHost's composition group never changes.
                    // While relocked it draws nothing of the shell and hides it from TalkBack: the
                    // first frame after a return may land before the lock window is attached.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .then(
                                if (relocked) {
                                    Modifier
                                        .clearAndSetSemantics {}
                                        .drawWithContent { drawRect(cover) }
                                } else {
                                    Modifier
                                },
                            ),
                    ) {
                        PersonalFinanceNavHost()
                    }
                    if (relocked && lock is PinLock.Set) {
                        LockOverlay {
                            PinUnlockScreen(
                                expectedHash = lock.secret.hash,
                                expectedSalt = lock.secret.salt,
                                biometricEnabled = biometricEnabled,
                                onUnlocked = session::unlock,
                            )
                        }
                    } else if (privacyCover) {
                        // The lock window already hides everything while relocked.
                        PrivacyCover()
                    }
                }
            }
        }
    }
}

/**
 * iOS's app-switcher cover (#319 AC-05, D-11): a plain surface in its own window, above any sheet
 * or dialog, for as long as Overview shows the app as a live tile.
 */
@Composable
private fun PrivacyCover() {
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surface)
                .testTag(PRIVACY_COVER_TAG),
        )
    }
}

internal const val PRIVACY_COVER_TAG = "privacyCover"

/**
 * The relock screen in its own full-screen window (#319 D-07), Android's `LockOverlayWindow`: a
 * window added now stacks above every sheet and dialog the shell already has open, so none of them
 * has to be torn down — the draft inside survives the lock.
 *
 * Back sends the app to the background (D-09) rather than trapping the user or dismissing the lock.
 */
@Composable
private fun LockOverlay(content: @Composable () -> Unit) {
    val activity = LocalContext.current as? Activity
    Dialog(
        onDismissRequest = { activity?.moveTaskToBack(true) },
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
        content = content,
    )
}

/** The production startup status used by both privacy-preserving probe branches (#137). */
@Composable
internal fun FoundationStartupLoadingState(message: String) {
    LoadingState(
        message = message,
        modifier = Modifier.fillMaxSize(),
    )
}
