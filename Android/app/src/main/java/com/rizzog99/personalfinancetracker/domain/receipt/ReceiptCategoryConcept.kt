package com.rizzog99.personalfinancetracker.domain.receipt

import androidx.annotation.StringRes
import com.rizzog99.personalfinancetracker.R

/**
 * A spending concept a receipt or a CSV category name can be recognized as, independent of what
 * the user calls their own category.
 *
 * Every other tier ends by matching a canonical concept against the *names* of the user's
 * categories, through the fixed synonym table in `CategoryAutoMapper`. That works only for someone
 * whose categories happen to be named in one of the languages that table covers. Categories are
 * user-created and user-renamed: "Uscite varie", "Gelati", a Polish or Portuguese name, or simply
 * "Fun" all identify a real category that no synonym reaches.
 *
 * So the user can state the pairing outright, once, and it is consulted before any name matching.
 * It is the only tier that cannot be wrong about what they meant.
 *
 * [key] is the canonical keyword `CategoryAutoMapper` already uses, so a keyword coming out of the
 * table maps straight onto one of these. Ported from iOS's `ReceiptCategoryConcept`, raw values
 * included, so the two platforms agree on what a stored pairing means.
 *
 * Entries may be added but never renamed or removed: [key] is the storage key a saved pairing lives
 * under, so renaming one silently discards the user's choice.
 */
enum class ReceiptCategoryConcept(
    val key: String,
    @StringRes val titleRes: Int,
    val iconToken: String,
) {
    RESTAURANT("restaurant", R.string.scan_category_restaurant, "fork.knife"),
    GROCER("grocer", R.string.scan_category_grocer, "cart"),
    TRANSPORT("transport", R.string.scan_category_transport, "bus"),
    GAS("gas", R.string.scan_category_gas, "fuelpump"),
    COFFEE("coffee", R.string.scan_category_coffee, "cup.and.saucer"),
    TRAVEL("travel", R.string.scan_category_travel, "airplane"),
    SHOPPING("shopping", R.string.scan_category_shopping, "bag"),
    CLOTH("cloth", R.string.scan_category_cloth, "tshirt"),
    HEALTH("health", R.string.scan_category_health, "cross.case"),
    FITNESS("fitness", R.string.scan_category_fitness, "dumbbell"),
    BEAUTY("beauty", R.string.scan_category_beauty, "comb"),
    ENTERTAIN("entertain", R.string.scan_category_entertain, "film"),
    EDU("edu", R.string.scan_category_edu, "graduationcap"),
    HOUSE("house", R.string.scan_category_house, "house.fill"),
    UTIL("util", R.string.scan_category_util, "bolt"),
    PHONE("phone", R.string.scan_category_phone, "iphone"),
    PET("pet", R.string.scan_category_pet, "pawprint"),
    GIFT("gift", R.string.scan_category_gift, "gift"),
    FEES("fees", R.string.scan_category_fees, "creditcard"),
    ;

    companion object {
        fun forKey(key: String): ReceiptCategoryConcept? = entries.firstOrNull { it.key == key }
    }
}
