package com.rizzog99.personalfinancetracker

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.fragment.app.FragmentActivity

/** FragmentActivity (not ComponentActivity) so androidx.biometric.BiometricPrompt can attach. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContent { PersonalFinanceTrackerApp() }
    }

    override fun onResume() {
        super.onResume()
        (application as PersonalFinanceApplication).materializeRecurringTransactions()
    }
}
