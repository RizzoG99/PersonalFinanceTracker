package com.rizzog99.personalfinancetracker.features.activity

import android.content.Context
import android.content.res.Configuration
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.R
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ActivityFilterCopyTest {
    @Test
    fun `AC-07 and AC-09 English clear actions describe their distinct effects`() {
        val context = localizedContext(Locale.ENGLISH)

        assertEquals("Clear filters", context.getString(R.string.clear_filters))
        assertEquals("Clear search and filters", context.getString(R.string.clear_search_and_filters))
        assertEquals("Any category", context.getString(R.string.filter_any_category))
        assertEquals(
            "Choose Income or Expense to filter by category.",
            context.getString(R.string.choose_type_for_categories),
        )
    }

    @Test
    fun `AC-07 and AC-09 Italian clear actions describe their distinct effects`() {
        val context = localizedContext(Locale.ITALIAN)

        assertEquals("Cancella filtri", context.getString(R.string.clear_filters))
        assertEquals("Cancella ricerca e filtri", context.getString(R.string.clear_search_and_filters))
        assertEquals("Qualsiasi categoria", context.getString(R.string.filter_any_category))
        assertEquals(
            "Scegli Entrate o Uscite per filtrare per categoria.",
            context.getString(R.string.choose_type_for_categories),
        )
    }

    private fun localizedContext(locale: Locale): Context {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val configuration = Configuration(context.resources.configuration).apply { setLocale(locale) }
        return context.createConfigurationContext(configuration)
    }
}
