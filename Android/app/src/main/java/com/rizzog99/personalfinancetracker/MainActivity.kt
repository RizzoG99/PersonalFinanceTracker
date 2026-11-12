package com.rizzog99.personalfinancetracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.fragment.app.FragmentActivity
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.features.security.AppLockSession

/** FragmentActivity (not ComponentActivity) so androidx.biometric.BiometricPrompt can attach. */
class MainActivity : FragmentActivity() {
    private val lockSession: AppLockSession by viewModels()

    private fun pinIsSet() =
        (application as PersonalFinanceApplication).pinLockRepository.state.value is PinLock.Set

    /**
     * The screen turned off: the grace is spent (#319 D-03, the Android stand-in for iOS's "device
     * locked"). Registered for the activity's whole life, so it also fires while backgrounded.
     */
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (pinIsSet()) lockSession.invalidateGrace()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Recents must never show finance content (#319 AC-05). Before setContent, so every sheet
        // and dialog window created later inherits FLAG_SECURE where it applies. D-02: API 33+
        // hides only the thumbnail and keeps screenshots working; below that, FLAG_SECURE is the
        // only reliable way.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        WindowCompat.setDecorFitsSystemWindows(window, false)
        ContextCompat.registerReceiver(
            this,
            screenOff,
            IntentFilter(Intent.ACTION_SCREEN_OFF),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        setContent { PersonalFinanceTrackerApp() }
    }

    /** Back from elsewhere: relock if the absence used up the grace. Before the first frame. */
    override fun onStart() {
        super.onStart()
        lockSession.relockIfGraceExpired(canRelock = pinIsSet())
    }

    override fun onResume() {
        super.onResume()
        (application as PersonalFinanceApplication).materializeRecurringTransactions()
    }

    /** A configuration change is not a departure (#136); anything else starts the grace. */
    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) lockSession.noteLeft()
    }

    /**
     * Overview shows this app as a *live* tile: the activity stays resumed, so neither
     * `setRecentsScreenshotEnabled(false)` nor `FLAG_SECURE` hides it (measured on API 36, #319
     * D-11). What does change is that another activity becomes top-resumed — and the app's own
     * sheets and dialogs never cause that. Frozen iOS covers the app whenever its scene is not
     * active; split-screen is the exception, as iPad keeps both scenes active there.
     */
    override fun onTopResumedActivityChanged(isTopResumedActivity: Boolean) {
        super.onTopResumedActivityChanged(isTopResumedActivity)
        // No focus release and no new window here: the keyboard may still be animating in, and either
        // one then crashed Compose 1.6's text input. Each window draws its own cover instead.
        lockSession.privacyCover = !isTopResumedActivity && !isInMultiWindowMode
    }

    /**
     * Paused means a translucent activity is on top — the notification-permission prompt, say —
     * not Overview (which keeps this activity resumed). Frozen iOS does not cover behind its own
     * prompts (#193), so neither does this. Leaving for good is covered by the Recents flags.
     */
    override fun onPause() {
        super.onPause()
        lockSession.privacyCover = false
    }

    override fun onDestroy() {
        unregisterReceiver(screenOff)
        super.onDestroy()
    }
}
