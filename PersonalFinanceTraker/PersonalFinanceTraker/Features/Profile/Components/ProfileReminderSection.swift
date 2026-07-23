//
//  ProfileReminderSection.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct ProfileReminderSection: View {
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 21
    @AppStorage("reminderMinute") private var reminderMinute = 0

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now
            ) ?? .now
        } set: { newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = comps.hour ?? 21
            reminderMinute = comps.minute ?? 0
            ReminderService.shared.reschedule(hasLoggedToday: false)
        }
    }

    var body: some View {
        Toggle(isOn: $reminderEnabled) {
            Label("Daily Reminder", systemImage: "bell.badge")
        }
        .onChange(of: reminderEnabled) { _, enabled in
            if enabled {
                Task {
                    let granted = await ReminderService.shared.requestPermission()
                    if granted {
                        ReminderService.shared.reschedule(hasLoggedToday: false)
                    } else {
                        reminderEnabled = false
                    }
                }
            } else {
                ReminderService.shared.reschedule(hasLoggedToday: false)
            }
        }
        if reminderEnabled {
            DatePicker(
                "Time", selection: reminderTime, displayedComponents: .hourAndMinute
            )
        }
    }
}
