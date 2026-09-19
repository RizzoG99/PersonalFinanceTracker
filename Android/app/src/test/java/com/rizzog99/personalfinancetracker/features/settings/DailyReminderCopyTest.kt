package com.rizzog99.personalfinancetracker.features.settings

import android.content.Context
import android.content.res.Configuration
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.R
import java.time.LocalTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #129: the reminder-time control's copy and its accessible description, in both shipped locales.
 * The description is what TalkBack reads for the row — a row whose only visible value is a
 * formatted time is useless without it.
 */
@RunWith(RobolectricTestRunner::class)
class DailyReminderCopyTest {

    @Test
    fun `English reminder settings name the control and its purpose`() {
        val context = localizedContext(Locale.US)

        assertEquals("Reminders", context.getString(R.string.reminders_section))
        assertEquals("Daily reminder", context.getString(R.string.daily_reminder))
        assertEquals("A nudge to log today's spending.", context.getString(R.string.daily_reminder_detail))
        assertEquals("Time", context.getString(R.string.reminder_time))
    }

    @Test
    fun `Italian reminder settings name the control and its purpose`() {
        val context = localizedContext(Locale.ITALY)

        assertEquals("Promemoria", context.getString(R.string.reminders_section))
        assertEquals("Promemoria giornaliero", context.getString(R.string.daily_reminder))
        assertEquals("Un invito a registrare le spese di oggi.", context.getString(R.string.daily_reminder_detail))
        assertEquals("Orario", context.getString(R.string.reminder_time))
    }

    @Test
    fun `the reminder time row reads its value out loud in both locales`() {
        val english = localizedContext(Locale.US)
        val italian = localizedContext(Locale.ITALY)
        val time = LocalTime.of(21, 0)

        assertEquals(
            "Reminder time, ${formatTimeOfDay(english, time)}",
            english.getString(R.string.reminder_time_description, formatTimeOfDay(english, time)),
        )
        assertEquals(
            "Orario del promemoria, ${formatTimeOfDay(italian, time)}",
            italian.getString(R.string.reminder_time_description, formatTimeOfDay(italian, time)),
        )
    }

    @Test
    fun `the displayed time follows the locale instead of a hardcoded pattern`() {
        // Not an assertion about one string: it pins that US and Italian render 21:00 differently,
        // which a hardcoded `HH:mm` (or `h:mm a`) could not do.
        val english = formatTimeOfDay(localizedContext(Locale.US), LocalTime.of(21, 0))
        val italian = formatTimeOfDay(localizedContext(Locale.ITALY), LocalTime.of(21, 0))

        assertEquals("9:00 PM", english)
        assertEquals("21:00", italian)
        // Midnight and one minute to midnight stay readable at both ends of the range.
        assertEquals("12:00 AM", formatTimeOfDay(localizedContext(Locale.US), LocalTime.MIDNIGHT))
        assertEquals("23:59", formatTimeOfDay(localizedContext(Locale.ITALY), LocalTime.of(23, 59)))
    }

    private fun localizedContext(locale: Locale): Context {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val configuration = Configuration(context.resources.configuration).apply { setLocale(locale) }
        return context.createConfigurationContext(configuration)
    }
}
