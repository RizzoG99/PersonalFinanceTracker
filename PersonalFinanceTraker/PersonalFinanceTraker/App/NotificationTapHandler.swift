//
//  NotificationTapHandler.swift
//  PersonalFinanceTraker
//

import UserNotifications

/// Turns a tap on a daily-log reminder into a pending "present Add sheet" intent.
/// NSObject is required by UNUserNotificationCenterDelegate.
final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapHandler()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            guard identifier.hasPrefix(ReminderService.idPrefix) else { return }
            PendingTransactionIntent.shared.shouldPresentAdd = true
        }
    }
}
