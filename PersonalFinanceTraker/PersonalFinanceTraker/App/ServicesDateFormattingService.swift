//
//  DateFormattingService.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import Foundation

/// Service for consistent date formatting across the application
///
/// This service provides standardized date formatting methods for financial
/// applications, with special handling for relative dates like "Today" and "Yesterday".
///
/// ## Usage
/// ```swift
/// let formatter = DateFormattingService()
/// let formattedDate = formatter.formatTransactionDate(Date())
/// // Returns: "Today"
/// ```
///
/// ## Features
/// - Relative date formatting ("Today", "Yesterday")
/// - Consistent date styles across the app
/// - Localization support
/// - Configurable date formats
public class DateFormattingService {
    
    private let calendar: Calendar
    private let dateFormatter: DateFormatter
    
    /// Creates a new date formatting service
    /// - Parameter calendar: Calendar to use for date calculations (defaults to current)
    public init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .medium
        self.dateFormatter.timeStyle = .none
    }
    
    /// Formats a date for transaction display with relative formatting
    /// - Parameter date: The date to format
    /// - Returns: Formatted date string ("Today", "Yesterday", or formatted date)
    public func formatTransactionDate(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return dateFormatter.string(from: date)
        }
    }
    
    /// Formats a date with a specific style
    /// - Parameters:
    ///   - date: The date to format
    ///   - dateStyle: The date style to use
    ///   - timeStyle: The time style to use
    /// - Returns: Formatted date string
    public func formatDate(_ date: Date, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .none) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
    
    /// Formats a date for chart axis labels
    /// - Parameters:
    ///   - date: The date to format
    ///   - timePeriod: The time period context for formatting
    /// - Returns: Appropriately formatted string for the time period
    public func formatChartAxisLabel(_ date: Date, for timePeriod: TimePeriod) -> String {
        let formatter = DateFormatter()
        
        switch timePeriod {
        case .week:
            formatter.dateFormat = "EEE" // Mon, Tue, Wed
        case .month:
            // For months, we might want week numbers or dates
            formatter.dateFormat = "MMM d" // Jan 15
        case .year:
            formatter.dateFormat = "MMM" // Jan, Feb, Mar
        }
        
        return formatter.string(from: date)
    }
    
    /// Gets the start of day for a given date
    /// - Parameter date: The input date
    /// - Returns: Date representing the start of the day
    public func startOfDay(for date: Date) -> Date {
        return calendar.startOfDay(for: date)
    }
    
    /// Gets the end of day for a given date
    /// - Parameter date: The input date
    /// - Returns: Date representing the end of the day
    public func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return calendar.date(byAdding: components, to: startOfDay(for: date)) ?? date
    }
    
    /// Checks if two dates are on the same day
    /// - Parameters:
    ///   - date1: First date
    ///   - date2: Second date
    /// - Returns: True if dates are on the same day
    public func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        return calendar.isDate(date1, inSameDayAs: date2)
    }
    
    /// Gets a date by adding a number of days to a reference date
    /// - Parameters:
    ///   - days: Number of days to add (can be negative)
    ///   - date: Reference date
    /// - Returns: New date with days added
    public func date(byAdding days: Int, to date: Date) -> Date? {
        return calendar.date(byAdding: .day, value: days, to: date)
    }
    
    /// Gets a date by adding a number of months to a reference date
    /// - Parameters:
    ///   - months: Number of months to add (can be negative)
    ///   - date: Reference date
    /// - Returns: New date with months added
    public func date(byAddingMonths months: Int, to date: Date) -> Date? {
        return calendar.date(byAdding: .month, value: months, to: date)
    }
    
    /// Gets a date by adding a number of weeks to a reference date
    /// - Parameters:
    ///   - weeks: Number of weeks to add (can be negative)
    ///   - date: Reference date
    /// - Returns: New date with weeks added
    public func date(byAddingWeeks weeks: Int, to date: Date) -> Date? {
        return calendar.date(byAdding: .weekOfYear, value: weeks, to: date)
    }
}

// MARK: - Extensions

extension DateFormattingService {
    /// Creates a date range for a specific time period ending at a reference date
    /// - Parameters:
    ///   - timePeriod: The time period to create a range for
    ///   - endDate: The end date of the range
    /// - Returns: A tuple containing the start and end dates
    public func dateRange(for timePeriod: TimePeriod, endingAt endDate: Date = Date()) -> (start: Date, end: Date) {
        let startDate = calendar.date(byAdding: .day, value: -timePeriod.days, to: endDate) ?? endDate
        return (start: startDate, end: endDate)
    }
    
    /// Groups dates by the specified time period
    /// - Parameters:
    ///   - dates: Array of dates to group
    ///   - timePeriod: Time period for grouping
    /// - Returns: Dictionary where keys are formatted period strings and values are arrays of dates
    public func groupDates(_ dates: [Date], by timePeriod: TimePeriod) -> [String: [Date]] {
        let grouped = Dictionary(grouping: dates) { date in
            formatChartAxisLabel(date, for: timePeriod)
        }
        return grouped
    }
}