package com.rizzog99.personalfinancetracker.data.local

/**
 * Stored data the app could not open at startup (#130, #131).
 *
 * `null` — the absence of this — is the normal case. Each value means the underlying file is still
 * on disk, untouched, and was *not* replaced with a working empty one: the app would rather stop
 * and say so than present a damaged install as a brand-new account.
 */
enum class StartupFailure {
    /** `personal_finance.db` could not be opened: transactions, goals, and history are unreadable. */
    DATABASE,

    /** `user_preferences.preferences_pb` could not be read: settings would otherwise read as defaults. */
    PREFERENCES,
}
