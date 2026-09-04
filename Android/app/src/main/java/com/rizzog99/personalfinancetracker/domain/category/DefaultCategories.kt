package com.rizzog99.personalfinancetracker.domain.category

object DefaultCategories {
    val all: List<NewCategory> = listOf(
        income("Salary", "banknote"),
        income("Gift", "gift"),
        income("Investment", "chart.line.uptrend.xyaxis"),
        income("Freelance", "briefcase"),
        income("Rental Income", "house"),
        income("Bonus", "star.circle"),
        income("Prize", "trophy"),
        income("Refund", "arrow.uturn.backward"),
        income("Other", "ellipsis.circle"),
        expense("Groceries", "cart"),
        expense("Restaurants", "fork.knife"),
        expense("Coffee & Drinks", "cup.and.saucer"),
        expense("Takeout", "takeoutbag.and.cup.and.straw"),
        expense("Gas", "fuelpump"),
        expense("Car Maintenance", "wrench.and.screwdriver"),
        expense("Public Transport", "bus"),
        expense("Taxi & Rideshare", "car"),
        expense("Rent/Mortgage", "house.fill"),
        expense("Utilities", "bolt"),
        expense("Phone Bill", "iphone"),
        expense("Internet", "globe"),
        expense("Streaming Services", "tv"),
        expense("Clothing", "tshirt"),
        expense("Shopping", "bag"),
        expense("Electronics", "gamecontroller"),
        expense("Books & Education", "book"),
        expense("Healthcare", "cross.case"),
        expense("Pharmacy", "pills"),
        expense("Gym & Fitness", "dumbbell"),
        expense("Personal Care", "comb"),
        expense("Entertainment", "film"),
        expense("Music", "music.note"),
        expense("Hobbies", "target"),
        expense("Travel", "airplane"),
        expense("Education", "graduationcap"),
        expense("Pets", "pawprint"),
        expense("Banking Fees", "creditcard"),
        expense("Other", "ellipsis.circle"),
    )

    private fun income(name: String, iconToken: String) = NewCategory(
        name = name,
        iconToken = iconToken,
        type = TransactionType.INCOME,
        colorToken = colorTokenFor(name),
    )

    private fun expense(name: String, iconToken: String) = NewCategory(
        name = name,
        iconToken = iconToken,
        type = TransactionType.EXPENSE,
        colorToken = colorTokenFor(name),
    )

    private fun colorTokenFor(name: String): String {
        val lower = name.lowercase()
        return when {
            listOf("grocer", "salary", "gift", "invest", "freelance", "bonus", "prize", "refund", "rental")
                .any(lower::contains) -> "categoryGreen"
            listOf("restaurant", "coffee", "takeout", "dining", "food", "entertainment")
                .any(lower::contains) -> "categoryAmber"
            listOf("gas", "car ", "transport", "taxi", "rideshare", "rent", "mortgage", "utilities", "phone", "internet", "banking")
                .any(lower::contains) -> "categoryIndigo"
            listOf("shopping", "clothing", "electronics").any(lower::contains) -> "categoryPink"
            listOf("streaming", "subscription", "music", "hobbies", "books").any(lower::contains) -> "categoryPurple"
            listOf("health", "gym", "fitness", "pharmacy", "pet", "personal care", "education").any(lower::contains) -> "categoryTeal"
            lower.contains("travel") -> "categoryAmber"
            else -> "categoryGray"
        }
    }
}
