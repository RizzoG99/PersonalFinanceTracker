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

    @Test
    fun `AC-02 AC-05 and AC-07 English validation explains rejected filter changes`() {
        val context = localizedContext(Locale.ENGLISH)

        assertEquals(
            "Enter amounts of zero or more, with the minimum no greater than the maximum.",
            context.getString(R.string.invalid_amount_range),
        )
        assertEquals(
            "The selected category is not available with these filters and was cleared.",
            context.getString(R.string.filter_category_cleared),
        )
    }

    @Test
    fun `AC-02 AC-05 and AC-07 Italian validation explains rejected filter changes`() {
        val context = localizedContext(Locale.ITALIAN)

        assertEquals(
            "Inserisci importi pari o superiori a zero, con il minimo non superiore al massimo.",
            context.getString(R.string.invalid_amount_range),
        )
        assertEquals(
            "La categoria selezionata non è disponibile con questi filtri ed è stata rimossa.",
            context.getString(R.string.filter_category_cleared),
        )
    }

    private fun localizedContext(locale: Locale): Context {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val configuration = Configuration(context.resources.configuration).apply { setLocale(locale) }
        return context.createConfigurationContext(configuration)
    }
}
