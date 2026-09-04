package com.rizzog99.personalfinancetracker

import android.app.Application
import androidx.room.Room
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository

class PersonalFinanceApplication : Application() {
    val database: PersonalFinanceDatabase by lazy {
        Room.databaseBuilder(this, PersonalFinanceDatabase::class.java, "personal_finance.db")
            .build()
    }

    val preferencesRepository: UserPreferencesRepository by lazy {
        UserPreferencesRepository(this)
    }
}
