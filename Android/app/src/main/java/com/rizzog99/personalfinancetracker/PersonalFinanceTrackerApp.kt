package com.rizzog99.personalfinancetracker

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.rizzog99.personalfinancetracker.navigation.PersonalFinanceNavHost

@Composable
fun PersonalFinanceTrackerApp() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            PersonalFinanceNavHost()
        }
    }
}
