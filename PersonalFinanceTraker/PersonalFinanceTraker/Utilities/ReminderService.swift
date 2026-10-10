//
//  ReminderService.swift
//  PersonalFinanceTraker
//

import Foundation
import UIKit
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

    /// The monthly recap notification (#193): 09:00 on the next payday, named after the cycle
    /// that closes then — the same name the recap card will show.
    static func recapFire(
        now: Date,
        payCycleStartDay: Int,
        calendar: Calendar = .current
    ) -> (date: Date, cycleName: String)? {
        let start = PayCycleService.financialMonthStart(for: now, startDay: payCycleStartDay, calendar: calendar)
        guard let payday = calendar.date(byAdding: .month, value: 1, to: start),
              let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: payday) else { return nil }
        return (fire, MonthlyRecap.cycleName(start: start, end: payday, calendar: calendar))
    }
}

@MainActor
@Observable
final class ReminderService {
    static let shared = ReminderService()
    /// The system permission alert is up. It deactivates the scene like the app switcher does,
    /// so the lock overlay would swap the privacy cover in behind it — read by
    /// `LockOverlayDecision` the same way as our Face ID prompt.
    private(set) var isPermissionPromptInFlight = false
    // nonisolated: an immutable constant read from the notification delegate
    // (a nonisolated context) as well as on the main actor.
    nonisolated static let idPrefix = "daily-log-reminder-"
    nonisolated static var reminderTitle: String {
        String(localized: "Log today's spending")
    }
    nonisolated static var reminderBody: String {
        String(localized: "Take 30 seconds to keep your streak.")
    }
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        // Only when the alert will really show: a flag left up with no alert would leave the
        // task-switcher snapshot uncovered.
        isPermissionPromptInFlight = await center.notificationSettings().authorizationStatus == .notDetermined
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        // Like Face ID: the scene is still inactive when the answer arrives and turns active a
        // moment later; clearing now would flash the cover in that gap. AuthenticationWrapper
        // ends it on `.active`/`.background`; if we're already active, end it here.
        if UIApplication.shared.applicationState == .active { isPermissionPromptInFlight = false }
        return granted
    }

    /// Called by AuthenticationWrapper when the scene is active again or truly backgrounded.
    func endPermissionPrompt() {
        isPermissionPromptInFlight = false
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

    nonisolated static let recapId = "monthly-recap"

    /// One request at the next payday, replaced on every call (by its own id only, so it and
    /// the daily reminder never remove each other). On unless turned off in Settings.
    /// `cycleHasActivity: false` skips it — "your recap is ready" for a card that won't show.
    /// ponytail: like the daily reminder, only rescheduled while the app runs.
    func scheduleMonthlyRecap(cycleHasActivity: Bool = true) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.recapId])
        let enabled = UserDefaults.standard.object(forKey: "recapNotificationEnabled") as? Bool ?? true
        guard enabled, cycleHasActivity,
              let fire = ReminderScheduler.recapFire(now: .now, payCycleStartDay: AppSettings.storedStartDay)
        else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your \(fire.cycleName) recap is ready")
        content.body = String(localized: "See what changed compared to the cycle before.")
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire.date)
        center.add(UNNotificationRequest(
            identifier: Self.recapId,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        ))
    }
}
