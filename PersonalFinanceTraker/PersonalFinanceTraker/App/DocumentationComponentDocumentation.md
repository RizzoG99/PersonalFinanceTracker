# Personal Finance Tracker - Component Documentation

## Overview

This document provides comprehensive documentation for all reusable components, models, and services extracted from the PersonalFinanceTracker application. Each component is designed to be modular, reusable, and well-documented to facilitate maintainability and testing.

## Architecture

The application follows a clean architecture pattern with the following layers:

- **Components**: Reusable UI components
- **Models**: Data models and structures
- **Services**: Business logic and data processing
- **Views**: Main application views (ContentView, etc.)

## Components

### TimePeriodPicker

**File**: `Components/TimePeriodPicker.swift`

A reusable segmented picker component for selecting time periods in financial views.

#### Purpose
- Provides consistent time period selection across the app
- Supports Week, Month, and Year selections
- Uses segmented picker style for easy interaction

#### Usage
```swift
@State private var selectedPeriod: TimePeriod = .month

TimePeriodPicker(selection: $selectedPeriod)
```

#### Features
- Automatic binding to TimePeriod enum
- Consistent styling across the app
- Supports all common financial time periods

---

### TransactionChart

**File**: `Components/TransactionChart.swift`

A reusable chart component for displaying financial transaction data using Swift Charts.

#### Purpose
- Displays income and expenses in a clear bar chart format
- Color-coded visualization (green for income, red for expenses)
- Supports different currencies and time periods

#### Usage
```swift
let chartData = [
    ChartDataPoint(period: "Mon", income: 1000, expenses: 500),
    ChartDataPoint(period: "Tue", income: 800, expenses: 600)
]

TransactionChart(data: chartData, currencyCode: "EUR")
```

#### Features
- Responsive bar chart with proper axis formatting
- Custom legend with color coding
- Configurable currency formatting
- Adjustable chart height
- Proper handling of positive/negative values

---

### FinancialSummaryCard

**File**: `Components/FinancialSummaryCard.swift`

A card component that displays financial summary information including income, expenses, and balance.

#### Purpose
- Presents financial totals in a clean, organized layout
- Color-coded amounts for quick visual understanding
- Automatic balance calculation

#### Usage
```swift
FinancialSummaryCard(
    income: 5000.00,
    expenses: -3000.00,
    currencyCode: "EUR"
)
```

#### Features
- Color-coded amounts (green for positive, red for negative)
- Proper typography hierarchy
- Support for different currencies
- Automatic balance calculation and color coding
- Consistent spacing and layout

---

### TransactionSectionHeader

**File**: `Components/TransactionSectionHeader.swift`

A header component for transaction list sections showing date and total amount.

#### Purpose
- Provides consistent section headers for transaction lists
- Shows both date and financial totals
- Color-coded totals based on positive/negative values

#### Usage
```swift
TransactionSectionHeader(
    dateString: "Today",
    totalAmount: 125.50,
    currencyCode: "EUR"
)
```

#### Features
- Displays formatted date strings
- Color-coded total amounts
- Consistent typography and spacing
- Support for different currencies

## Models

### ChartDataPoint

**File**: `Models/ChartDataPoint.swift`

A structure representing a single data point in financial charts.

#### Purpose
- Encapsulates financial data for specific time periods
- Provides calculated properties for analysis
- Used by chart components and services

#### Properties
- `period: String` - Time period label (e.g., "Mon", "Week 1", "Jan")
- `income: Decimal` - Total income for the period
- `expenses: Decimal` - Total expenses for the period (positive value)
- `netAmount: Decimal` - Calculated net amount (income - expenses)

#### Computed Properties
- `hasActivity: Bool` - Whether the period has any financial activity
- `isProfit: Bool` - Whether income exceeds expenses
- `isLoss: Bool` - Whether expenses exceed income
- `isBreakEven: Bool` - Whether income equals expenses

#### Usage
```swift
let dataPoint = ChartDataPoint(
    period: "January",
    income: 5000.00,
    expenses: 3000.00
)

print("Net amount: \(dataPoint.netAmount)") // 2000.00
print("Is profitable: \(dataPoint.isProfit)") // true
```

---

### TimePeriod

**File**: `Components/TimePeriodPicker.swift` (embedded enum)

An enumeration representing different time periods for financial analysis.

#### Purpose
- Standardizes time period definitions across the app
- Provides day calculations for filtering
- Used by charts, services, and UI components

#### Cases
- `.week` - 7 days
- `.month` - 30 days
- `.year` - 365 days

#### Properties
- `days: Int` - Number of days for the time period
- `description: String` - Human-readable description

## Services

### ChartDataService

**File**: `Services/ChartDataService.swift`

Service class for generating chart data from financial transactions.

#### Purpose
- Processes raw transaction data into chart-ready format
- Handles time period filtering and aggregation
- Provides business logic for chart generation

#### Key Methods

##### `generateChartData(from:for:referenceDate:)`
Generates chart data points from a collection of financial items.

**Parameters:**
- `items: [Item]` - Array of financial items to process
- `timePeriod: TimePeriod` - Time period for data aggregation
- `referenceDate: Date` - Reference date for calculations (defaults to current date)

**Returns:** `[ChartDataPoint]` - Array of chart data points ready for display

##### `filterItems(_:for:referenceDate:)`
Filters items based on the specified time period.

**Parameters:**
- `items: [Item]` - Array of items to filter
- `timePeriod: TimePeriod` - Time period for filtering
- `referenceDate: Date` - Reference date for calculations

**Returns:** `[Item]` - Filtered array of items within the time period

##### `getSummaryStats(from:for:)`
Gets summary statistics for a time period.

**Parameters:**
- `items: [Item]` - Array of items to analyze
- `timePeriod: TimePeriod` - Time period for analysis

**Returns:** `(income: Decimal, expenses: Decimal, net: Decimal)` - Summary statistics tuple

#### Usage
```swift
let service = ChartDataService()
let chartData = service.generateChartData(
    from: transactions,
    for: .month
)

let stats = service.getSummaryStats(from: transactions, for: .week)
print("Weekly income: \(stats.income)")
```

#### Features
- Supports week, month, and year aggregations
- Automatic date grouping and filtering
- Proper handling of income vs expenses
- Configurable reference dates for testing
- Summary statistics generation

---

### DateFormattingService

**File**: `Services/DateFormattingService.swift`

Service for consistent date formatting across the application.

#### Purpose
- Provides standardized date formatting methods
- Handles relative dates ("Today", "Yesterday")
- Supports localization and different date styles

#### Key Methods

##### `formatTransactionDate(_:)`
Formats a date for transaction display with relative formatting.

**Parameters:**
- `date: Date` - The date to format

**Returns:** `String` - Formatted date string ("Today", "Yesterday", or formatted date)

##### `formatChartAxisLabel(_:for:)`
Formats a date for chart axis labels based on time period context.

**Parameters:**
- `date: Date` - The date to format
- `timePeriod: TimePeriod` - The time period context

**Returns:** `String` - Appropriately formatted string for the time period

##### `dateRange(for:endingAt:)`
Creates a date range for a specific time period.

**Parameters:**
- `timePeriod: TimePeriod` - The time period to create a range for
- `endDate: Date` - The end date of the range (defaults to current date)

**Returns:** `(start: Date, end: Date)` - A tuple containing start and end dates

#### Usage
```swift
let formatter = DateFormattingService()
let formattedDate = formatter.formatTransactionDate(Date())
// Returns: "Today"

let chartLabel = formatter.formatChartAxisLabel(date, for: .week)
// Returns: "Mon" for week view

let (start, end) = formatter.dateRange(for: .month)
// Returns: (30 days ago, today)
```

#### Features
- Relative date formatting for recent dates
- Context-aware chart label formatting
- Date range calculations for filtering
- Localization support
- Consistent formatting across the app

## Integration Examples

### Basic Chart Implementation

```swift
struct MyFinanceView: View {
    @State private var selectedPeriod: TimePeriod = .month
    let transactions: [Item]
    
    private let chartService = ChartDataService()
    
    var body: some View {
        VStack {
            TimePeriodPicker(selection: $selectedPeriod)
            
            TransactionChart(
                data: chartService.generateChartData(
                    from: transactions, 
                    for: selectedPeriod
                ),
                currencyCode: "USD"
            )
            
            FinancialSummaryCard(
                income: calculateIncome(),
                expenses: calculateExpenses(),
                currencyCode: "USD"
            )
        }
    }
}
```

### Custom Chart with Service Integration

```swift
struct DetailedAnalyticsView: View {
    let transactions: [Item]
    @State private var selectedPeriod: TimePeriod = .year
    
    private let chartService = ChartDataService()
    private let dateFormatter = DateFormattingService()
    
    var body: some View {
        VStack {
            TimePeriodPicker(selection: $selectedPeriod)
            
            TransactionChart(
                data: chartService.generateChartData(
                    from: transactions,
                    for: selectedPeriod
                ),
                currencyCode: "EUR",
                chartHeight: 300
            )
            
            let stats = chartService.getSummaryStats(
                from: transactions,
                for: selectedPeriod
            )
            
            FinancialSummaryCard(
                income: stats.income,
                expenses: -stats.expenses, // Convert back to negative
                currencyCode: "EUR"
            )
        }
    }
}
```

## Testing Guidelines

### Unit Testing Components

Components should be tested using SwiftUI's testing capabilities:

```swift
import Testing
@testable import PersonalFinanceTracker

@Suite("Chart Data Point Tests")
struct ChartDataPointTests {
    
    @Test("Net amount calculation")
    func netAmountCalculation() {
        let dataPoint = ChartDataPoint(
            period: "Test",
            income: 1000,
            expenses: 600
        )
        
        #expect(dataPoint.netAmount == 400)
        #expect(dataPoint.isProfit == true)
    }
    
    @Test("Loss detection")
    func lossDetection() {
        let dataPoint = ChartDataPoint(
            period: "Test",
            income: 500,
            expenses: 800
        )
        
        #expect(dataPoint.isLoss == true)
        #expect(dataPoint.isProfit == false)
    }
}
```

### Service Testing

Services should be tested with various data scenarios:

```swift
@Suite("Chart Data Service Tests")
struct ChartDataServiceTests {
    
    @Test("Weekly data generation")
    func weeklyDataGeneration() async throws {
        let service = ChartDataService()
        let testItems = createTestItems()
        
        let chartData = service.generateChartData(
            from: testItems,
            for: .week
        )
        
        #expect(chartData.count == 7)
        #expect(chartData.first?.period == "Mon")
    }
}
```

## Best Practices

### Component Design
1. **Single Responsibility**: Each component should have one clear purpose
2. **Reusability**: Design components to work in multiple contexts
3. **Configuration**: Use parameters for customization rather than hardcoding
4. **Documentation**: Include comprehensive documentation and usage examples

### State Management
1. **Minimal State**: Keep component state minimal and focused
2. **Binding Usage**: Use `@Binding` for two-way communication
3. **Service Injection**: Inject services rather than creating them internally

### Performance
1. **Lazy Loading**: Use lazy evaluation for expensive calculations
2. **Caching**: Cache formatted strings and computed values when appropriate
3. **Memory Management**: Avoid retain cycles in closures and delegates

### Error Handling
1. **Graceful Degradation**: Handle missing or invalid data gracefully
2. **User Feedback**: Provide clear error messages when appropriate
3. **Logging**: Log errors for debugging purposes

## Future Enhancements

### Planned Components
1. **CategorySelector**: Reusable category selection component
2. **AmountInput**: Standardized amount input with validation
3. **DateRangePicker**: Date range selection for custom periods
4. **ExportButton**: Reusable export functionality

### Service Improvements
1. **CurrencyService**: Centralized currency handling and conversion
2. **ValidationService**: Input validation and business rules
3. **ExportService**: Data export functionality
4. **NotificationService**: User notification management

This documentation should be updated as components evolve and new features are added.