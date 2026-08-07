//
//  NotificationTapHandler.swift
//  PersonalFinanceTraker
//

import UserNotifications

/// Turns a tap on a daily-log reminder into a pending "present Add sheet" intent.
/// NSObject is required by UNUserNotificationCenterDelegate.
final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapHandler()

    // Deliberately the completion-handler (synchronous) delegate variant, NOT the
    // `async` one. The async variant completes on Swift's cooperative thread pool, and
    // UIKit's post-response housekeeping (`_updateStateRestorationArchiveForBackgroundEvent`
    // → `_performBlockAfterCATransactionCommitSynchronizes`) then runs off the main
    // thread and trips a "must be made on main thread" assertion, crashing the app when a
    // reminder is tapped. Hopping to the main queue and invoking `completionHandler` there
    // keeps that housekeeping on the main thread.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isReminder = response.notification.request.identifier.hasPrefix(ReminderService.idPrefix)
        DispatchQueue.main.async {
            if isReminder { PendingTransactionIntent.shared.shouldPresentAdd = true }
            completionHandler()
        }
    }
}
