package com.rizzog99.personalfinancetracker

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.features.security.PinUnlockScreen
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode

@Composable
fun PersonalFinanceTrackerApp() {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val themeMode by application.preferencesRepository.themeMode.collectAsState(initial = ThemeMode.SYSTEM)
    val pinLock by application.pinLockRepository.state.collectAsState()
    val biometricEnabled by application.preferencesRepository.biometricEnabled.collectAsState(initial = false)
    // Unlocked once per process — a PIN gates cold starts, not every foreground resume.
    var unlocked by remember { mutableStateOf(false) }

    PersonalFinanceTheme(themeMode = themeMode) {
        when (val lock = pinLock) {
            // Reading the secret means a file read plus a Keystore decrypt. Hold on the plain app
            // background until that answers, rather than flashing the dashboard at someone the
            // lock screen is about to stop.
            PinLock.Unknown -> Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {}
            is PinLock.Set -> if (unlocked) {
                PersonalFinanceNavHost()
            } else {
                PinUnlockScreen(
                    expectedHash = lock.secret.hash,
                    expectedSalt = lock.secret.salt,
                    biometricEnabled = biometricEnabled,
                    onUnlocked = { unlocked = true },
                )
            }
            PinLock.NotSet -> PersonalFinanceNavHost()
        }
    }
}
