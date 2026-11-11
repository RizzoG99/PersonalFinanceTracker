package com.rizzog99.personalfinancetracker

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.SideEffect
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
    val lockState by session.state.collectAsState()

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
                SideEffect { session.unlock() }
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
