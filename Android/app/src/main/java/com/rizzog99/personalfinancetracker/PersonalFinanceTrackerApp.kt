package com.rizzog99.personalfinancetracker

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.data.local.StartupFailure
import com.rizzog99.personalfinancetracker.data.security.PinLock
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
    // Unlocked once per process — a PIN gates cold starts, not every foreground resume.
    val session: AppLockSession = viewModel()

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
        // `unlocked` means "this process is past the app-lock gate", which is why the shell below
        // has exactly *one* call site. Two would not do: `pinLock` is a flow, not a launch-time
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
            !session.unlocked && lock is PinLock.Unknown ->
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                    FoundationStartupLoadingState(
                        message = stringResource(R.string.startup_loading_security),
                    )
                }
            !session.unlocked && lock is PinLock.Set -> PinUnlockScreen(
                expectedHash = lock.secret.hash,
                expectedSalt = lock.secret.salt,
                biometricEnabled = biometricEnabled,
                onUnlocked = { session.unlocked = true },
            )
            else -> {
                SideEffect { session.unlocked = true }
                PersonalFinanceNavHost()
            }
        }
    }
}

/** The production startup status used by both privacy-preserving probe branches (#137). */
@Composable
internal fun FoundationStartupLoadingState(message: String) {
    LoadingState(
        message = message,
        modifier = Modifier.fillMaxSize(),
    )
}

/**
 * "This process is past the app-lock gate", held where a configuration change cannot reach it.
 *
 * A `remember`ed flag here was #136: the composition dies with the activity, so a locale change —
 * or a rotation, or a dark-mode switch — reset it to `false`, put `PinUnlockScreen` in front of a
 * session already past the gate, and took `PersonalFinanceNavHost` out of the composition with the
 * user's selected destination inside it. That is the same shell loss as #132, reached by
 * recreation instead of by a mid-session PIN set.
 *
 * ponytail: a `ViewModel` holding one boolean, not `rememberSaveable`. The distinction is the whole
 * point. `rememberSaveable` writes to the saved-instance-state bundle, which Android restores after
 * a **process kill** — so a cold start would come back already unlocked and skip the PIN entirely.
 * A `ViewModel` is retained across configuration changes and dies with the process, which is
 * exactly the "once per process" lifetime the gate is documented to have.
 */
internal class AppLockSession : ViewModel() {
    var unlocked by mutableStateOf(false)
}
