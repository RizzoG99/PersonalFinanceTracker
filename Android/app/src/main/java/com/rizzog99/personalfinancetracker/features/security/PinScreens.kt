package com.rizzog99.personalfinancetracker.features.security

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Backspace
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import kotlinx.coroutines.delay

const val PIN_LENGTH = 6

/** Two-stage PIN creation: enter, then confirm. Used for first-time setup and for "Change PIN". */
@Composable
fun PinSetupScreen(
    onCancel: () -> Unit,
    onPinCreated: (pin: String) -> Unit,
) {
    var firstEntry by remember { mutableStateOf<String?>(null) }
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }

    LaunchedEffect(entered) {
        if (entered.length < PIN_LENGTH) return@LaunchedEffect
        val first = firstEntry
        if (first == null) {
            firstEntry = entered
            entered = ""
        } else if (entered == first) {
            onPinCreated(entered)
        } else {
            error = true
            delay(400)
            error = false
            firstEntry = null
            entered = ""
        }
    }

    PinScaffold(
        title = if (firstEntry == null) stringResource(R.string.pin_create_title) else stringResource(R.string.pin_confirm_title),
        subtitle = stringResource(R.string.pin_digits_hint, PIN_LENGTH),
        pinLength = PIN_LENGTH,
        filledCount = entered.length,
        isError = error,
        errorMessage = null,
        onDigit = { if (entered.length < PIN_LENGTH) entered += it },
        onBackspace = { if (entered.isNotEmpty()) entered = entered.dropLast(1) },
        onClose = onCancel,
    )
}

/** App-lock gate: verify the stored PIN, with an optional biometric shortcut. */
@Composable
fun PinUnlockScreen(
    expectedHash: String,
    expectedSalt: String,
    biometricEnabled: Boolean,
    onUnlocked: () -> Unit,
) {
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val activity = context as? FragmentActivity

    LaunchedEffect(entered) {
        if (entered.length < PIN_LENGTH) return@LaunchedEffect
        if (PinCodec.matches(entered, expectedSalt, expectedHash)) {
            onUnlocked()
        } else {
            error = true
            delay(400)
            entered = ""
        }
    }

    LaunchedEffect(biometricEnabled, activity) {
        if (!biometricEnabled || activity == null) return@LaunchedEffect
        val canAuthenticate = BiometricManager.from(activity)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        if (canAuthenticate != BiometricManager.BIOMETRIC_SUCCESS) return@LaunchedEffect
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    onUnlocked()
                }
            },
        )
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(activity.getString(R.string.biometric_unlock))
                .setNegativeButtonText(activity.getString(R.string.use_pin_instead))
                .build(),
        )
    }

    PinScaffold(
        title = stringResource(R.string.pin_unlock_title),
        subtitle = null,
        pinLength = PIN_LENGTH,
        filledCount = entered.length,
        isError = error,
        errorMessage = if (error) stringResource(R.string.pin_incorrect) else null,
        onDigit = {
            if (error) error = false
            if (entered.length < PIN_LENGTH) entered += it
        },
        onBackspace = { if (entered.isNotEmpty()) entered = entered.dropLast(1) },
        onClose = null,
    )
}

@Composable
private fun PinScaffold(
    title: String,
    subtitle: String?,
    pinLength: Int,
    filledCount: Int,
    isError: Boolean,
    errorMessage: String?,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    onClose: (() -> Unit)?,
) {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (onClose != null) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.dismiss))
                    }
                }
            } else {
                Spacer(Modifier.height(48.dp))
            }
            Spacer(Modifier.height(24.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.semantics { heading() },
            )
            if (subtitle != null) {
                Spacer(Modifier.height(8.dp))
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(32.dp))
            PinDots(pinLength = pinLength, filledCount = filledCount, isError = isError)
            if (errorMessage != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
                )
            }
            Spacer(Modifier.weight(1f))
            PinKeypad(
                onDigit = onDigit,
                onBackspace = onBackspace,
                backspaceEnabled = filledCount > 0,
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun PinDots(pinLength: Int, filledCount: Int, isError: Boolean) {
    val color = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        repeat(pinLength) { index ->
            Box(
                modifier = Modifier
                    .size(14.dp)
                    .background(
                        color = if (index < filledCount) color else MaterialTheme.colorScheme.outlineVariant,
                        shape = CircleShape,
                    ),
            )
        }
    }
}

@Composable
private fun PinKeypad(
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    backspaceEnabled: Boolean,
) {
    val rows = listOf("123", "456", "789", " 0⌫")
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                row.forEach { char ->
                    when (char) {
                        ' ' -> Spacer(Modifier.size(72.dp))
                        '⌫' -> IconButton(
                            onClick = onBackspace,
                            enabled = backspaceEnabled,
                            modifier = Modifier.size(72.dp),
                        ) {
                            Icon(Icons.AutoMirrored.Outlined.Backspace, contentDescription = stringResource(R.string.backspace))
                        }
                        else -> KeypadButton(digit = char, onClick = { onDigit(char) })
                    }
                }
            }
        }
    }
}

@Composable
private fun KeypadButton(digit: Char, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier
            .size(72.dp)
            .aspectRatio(1f)
            .semantics { role = Role.Button },
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(digit.toString(), style = MaterialTheme.typography.headlineSmall)
        }
    }
}
