//
//  ReminderService.swift
//  PersonalFinanceTraker
//

import Foundation
import UserNotifications

/// Pure scheduling decisions, separated from UNUserNotificationCenter for tests.
struct ReminderScheduler {
    /// Next 7 daily fire dates at hour:minute. Today is skipped when the user
    /// already completed their check-in or the time has already passed.
    static func fireDates(
        now: Date,
        hour: Int,
        minute: Int,
        hasCompletedToday: Bool,
        calendar: Calendar = .current
    ) -> [Date] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                  )
            else { return nil }
            if offset == 0 && (hasCompletedToday || fire <= now) { return nil }
            return fire
        }
    }
}

@MainActor
final class ReminderService {
    static let shared = ReminderService()
    // nonisolated: an immutable constant read from the notification delegate
    // (a nonisolated context) as well as on the main actor.
    nonisolated static let idPrefix = "daily-log-reminder-"
    nonisolated static let reminderTitle = "Log today's spending"
    nonisolated static let reminderBody = "Take 30 seconds to keep your streak."
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// ponytail: 7 one-shot requests, rescheduled on scene-phase changes — no
    /// background task. If the app isn't opened for a week, reminders stop
    /// until next launch; add BGAppRefresh if that ever matters.
    func reschedule(hasCompletedToday: Bool) {
        center.removePendingNotificationRequests(
            withIdentifiers: (0..<7).map { "\(Self.idPrefix)\($0)" }
        )
        guard UserDefaults.standard.bool(forKey: "reminderEnabled") else { return }
        let hour = UserDefaults.standard.object(forKey: "reminderHour") as? Int ?? 21
        let minute = UserDefaults.standard.object(forKey: "reminderMinute") as? Int ?? 0

        let dates = ReminderScheduler.fireDates(
            now: .now, hour: hour, minute: minute, hasCompletedToday: hasCompletedToday
        )
        for (i, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = Self.reminderTitle
            content.body = Self.reminderBody
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            center.add(UNNotificationRequest(
                identifier: "\(Self.idPrefix)\(i)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            ))
        }
    }
}
