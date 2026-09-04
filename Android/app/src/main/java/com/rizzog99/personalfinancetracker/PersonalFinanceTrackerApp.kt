package com.rizzog99.personalfinancetracker

import androidx.compose.runtime.Composable
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme

@Composable
fun PersonalFinanceTrackerApp() {
    PersonalFinanceTheme {
        PersonalFinanceNavHost()
    }
}
