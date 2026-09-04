package com.rizzog99.personalfinancetracker.domain.category

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoryNameValidatorTest {
    @Test
    fun `accepts iOS-compatible names with common punctuation`() {
        assertTrue(CategoryNameValidator.isValid("Photography & Videomaking"))
        assertTrue(CategoryNameValidator.isValid("Rent/Mortgage"))
        assertTrue(CategoryNameValidator.isValid("Kids' Activities - Summer"))
        assertTrue(CategoryNameValidator.isValid("Caffè, Bar (Downtown)"))
    }

    @Test
    fun `rejects unsupported category characters`() {
        assertFalse(CategoryNameValidator.isValid("Food < Groceries"))
        assertFalse(CategoryNameValidator.isValid("Bills @ Home"))
    }

    @Test
    fun `finds duplicates regardless of case or surrounding whitespace`() {
        assertTrue(CategoryNameValidator.isDuplicate("  OTHER ", sequenceOf("Groceries", "Other")))
        assertFalse(CategoryNameValidator.isDuplicate("Other", sequenceOf("Groceries", "Salary")))
    }
}
