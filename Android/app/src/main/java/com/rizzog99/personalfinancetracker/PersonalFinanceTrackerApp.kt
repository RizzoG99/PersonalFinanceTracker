package com.rizzog99.personalfinancetracker

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode

@Composable
fun PersonalFinanceTrackerApp() {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val themeMode by application.preferencesRepository.themeMode.collectAsState(initial = ThemeMode.SYSTEM)

    PersonalFinanceTheme(themeMode = themeMode) {
        PersonalFinanceNavHost()
    }
}
