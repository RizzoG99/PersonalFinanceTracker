# Personal Finance Tracker · iOS

A personal finance app for tracking income and expenses, understanding spending patterns, and staying on top of your finances.

**Requirements:** iOS 26+

---

## Features

- **Dashboard** — total balance, income/expense summary for the current pay cycle, and recent transactions
- **Activity** — full transaction list with grouped history and swipe-to-delete with undo
- **Insights** — spending breakdown by category with charts and narrative summaries
- **Categories** — customizable categories with icons and colors
- **Add / Edit transactions** — quick entry sheet with category, amount, date, and notes
- **Profile** — pay cycle configuration and personal info

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Architecture | MVVM |
| Tests | Swift Testing |

## Work in Progress

- Biometric authorization
- Full-text search
- iCloud sync
- Budgeting / spending limits

## Development

Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` in Xcode. Build and run on a simulator or device running iOS 26+.

> **Note:** The project directory is spelled `PersonalFinanceTraker` (one 'c') — this is a known typo carried throughout the Xcode project.
