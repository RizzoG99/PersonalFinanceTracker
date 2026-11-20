package com.rizzog99.personalfinancetracker.features.security

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.security.PinSecret
import com.rizzog99.personalfinancetracker.domain.security.PinCodec

/**
 * Proves the user knows the current PIN before a sensitive action (#320): frozen iOS
 * `PINSetupViewModel.verifyCurrentPIN` for Change PIN and `PINConfirmationView` for Delete All Data.
 * ✕ and system Back cancel. Wrong guesses are unlimited, like the app lock (D-01, #427).
 */
@Composable
fun PinVerifyScreen(
    title: String,
    subtitle: String?,
    secret: PinSecret,
    onVerified: () -> Unit,
    onCancel: () -> Unit,
) {
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }

    BackHandler(onBack = onCancel)

    LaunchedEffect(entered) {
        if (entered.length < PIN_LENGTH) return@LaunchedEffect
        if (PinCodec.matches(entered, secret.salt, secret.hash)) {
            onVerified()
        } else {
            // Cleared at once, the message staying until the next digit: a delayed clear would
            // swallow the digits of a quick retry.
            error = true
            entered = ""
        }
    }

    PinScaffold(
        title = title,
        subtitle = subtitle,
        pinLength = PIN_LENGTH,
        filledCount = entered.length,
        isError = error,
        errorMessage = if (error) stringResource(R.string.pin_incorrect) else null,
        onDigit = {
            if (error) error = false
            if (entered.length < PIN_LENGTH) entered += it
        },
        onBackspace = { if (entered.isNotEmpty()) entered = entered.dropLast(1) },
        onClose = onCancel,
    )
}
