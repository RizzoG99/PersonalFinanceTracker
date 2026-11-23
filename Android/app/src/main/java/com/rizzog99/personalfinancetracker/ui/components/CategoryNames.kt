package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.import.removingLeadingEmoji

/**
 * Built-in categories are stored under their English name and translated only for display (#291,
 * iOS `localizedCategoryDisplay`), so they follow the app language. Any stored name equal to a key
 * is translated, as on iOS; every other name is shown as the user typed it.
 */
internal val builtInCategoryNames: Map<String, Int> = mapOf(
    "Salary" to R.string.builtin_category_salary,
    "Gift" to R.string.builtin_category_gift,
    "Investment" to R.string.builtin_category_investment,
    "Freelance" to R.string.builtin_category_freelance,
    "Rental Income" to R.string.builtin_category_rental_income,
    "Bonus" to R.string.builtin_category_bonus,
    "Prize" to R.string.builtin_category_prize,
    "Refund" to R.string.builtin_category_refund,
    "Other" to R.string.builtin_category_other,
    "Groceries" to R.string.builtin_category_groceries,
    "Restaurants" to R.string.builtin_category_restaurants,
    "Coffee & Drinks" to R.string.builtin_category_coffee_drinks,
    "Takeout" to R.string.builtin_category_takeout,
    "Gas" to R.string.builtin_category_gas,
    "Car Maintenance" to R.string.builtin_category_car_maintenance,
    "Public Transport" to R.string.builtin_category_public_transport,
    "Taxi & Rideshare" to R.string.builtin_category_taxi_rideshare,
    "Rent/Mortgage" to R.string.builtin_category_rent_mortgage,
    "Utilities" to R.string.builtin_category_utilities,
    "Phone Bill" to R.string.builtin_category_phone_bill,
    "Internet" to R.string.builtin_category_internet,
    "Streaming Services" to R.string.builtin_category_streaming_services,
    "Clothing" to R.string.builtin_category_clothing,
    "Shopping" to R.string.builtin_category_shopping,
    "Electronics" to R.string.builtin_category_electronics,
    "Books & Education" to R.string.builtin_category_books_education,
    "Healthcare" to R.string.builtin_category_healthcare,
    "Pharmacy" to R.string.builtin_category_pharmacy,
    "Gym & Fitness" to R.string.builtin_category_gym_fitness,
    "Personal Care" to R.string.builtin_category_personal_care,
    "Entertainment" to R.string.builtin_category_entertainment,
    "Music" to R.string.builtin_category_music,
    "Hobbies" to R.string.builtin_category_hobbies,
    "Travel" to R.string.builtin_category_travel,
    "Education" to R.string.builtin_category_education,
    "Pets" to R.string.builtin_category_pets,
    "Banking Fees" to R.string.builtin_category_banking_fees,
)

/** Every built-in key → its name in the current language, for code that cannot call [stringResource] (search). */
@Composable
fun categoryDisplayNames(): Map<String, String> = builtInCategoryNames.mapValues { (_, id) -> stringResource(id) }

/** What a stored category name looks like on screen: a built-in's translation, else the name itself. */
@Composable
fun categoryDisplayName(stored: String): String =
    builtInCategoryNames[stored.removingLeadingEmoji().trim()]?.let { stringResource(it) } ?: stored
