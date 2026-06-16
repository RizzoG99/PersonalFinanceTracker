# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal Finance Tracker is an iOS app (iOS 26+) built with SwiftUI and SwiftData that helps users track income and expenses with visual analytics.

## Build & Development Commands

### Building & Running
```bash
# Build the project
xcodebuild -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj -scheme PersonalFinanceTraker -configuration Debug build

# Run tests
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj -scheme PersonalFinanceTraker -destination 'platform=iOS Simulator,name=iPhone 15'

# Run unit tests only
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj -scheme PersonalFinanceTraker -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PersonalFinanceTrakerTests

# Run UI tests only
xcodebuild test -project PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj -scheme PersonalFinanceTraker -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PersonalFinanceTrakerUITests
```

**Note**: The project is primarily developed in Xcode. Open `PersonalFinanceTraker/PersonalFinanceTraker.xcodeproj` to work in the IDE.

## Architecture

### MVVM Pattern

This codebase strictly follows **MVVM (Model-View-ViewModel)** with clear separation:

- **Models** (`/Models`): SwiftData entities and data structures
- **ViewModels** (`/Features/*/ViewModels`): Business logic, state management, Combine pipelines
- **Views** (`/Features/*/Views`): SwiftUI declarative UI
- **Repositories** (`/Models/TransactionRepository.swift`): Protocol-based data access layer

### Data Flow

```
View → ViewModel (via @Published bindings) → Repository → SwiftData
     ← Reactive updates ← Combine subscribers ←
```

**Key Points**:
- ViewModels use `@Published` properties with Combine's `sink` for reactive pipelines
- Views observe ViewModels via `@StateObject` or `@EnvironmentObject`
- Repository pattern (`ITransactionRepository` protocol) abstracts data access
- SwiftData handles persistence (NOT CoreData)

### Project Structure

```
PersonalFinanceTraker/PersonalFinanceTraker/
├── App/                          # App entry point and configuration
│   └── PersonalFinanceTrakerApp.swift  # SwiftData ModelContainer setup, sample data injection
├── Features/                     # Feature-based organization (MVVM structure)
│   ├── MainTabView/             # Tab-based navigation container
│   ├── TransactionListView/     # Transaction list with chart (View, ViewModel, Components)
│   ├── EditAddTransactionView/  # Add/Edit transaction form (View, ViewModel, Components)
│   └── CategoryBreakdown/       # Category analytics (View, ViewModel, Components)
├── Models/                       # Data models and repository
│   ├── TransactionModel.swift   # SwiftData @Model entity
│   ├── TransactionRepository.swift  # Protocol-based repository pattern
│   ├── TransactionCategory.swift    # Predefined categories (28 expense, 8 income)
│   ├── TransactionType.swift    # Income/Expense enum with colors
│   ├── ChartDataPoint.swift     # Time-series chart data
│   └── PieChartDataPoint.swift  # Category breakdown data
└── Utilities/                    # Services and helpers
    ├── ChartDataService.swift       # Time-series aggregation (daily/weekly/monthly)
    ├── PieChartDataService.swift    # Category grouping with percentages
    ├── DateFormattingService.swift  # Relative date formatting ("Today", "Yesterday")
    └── SampleData.swift             # DEBUG build sample data generator
```

### SwiftData Persistence

- **Framework**: SwiftData (NOT CoreData)
- **Schema**: Single entity `TransactionModel` with properties: `timestamp`, `amount` (Decimal), `note`, `category`, `idCategory`
- **Configuration**: Persisted to device (not in-memory)
- **Sample Data**: Automatically injected in DEBUG builds if database is empty (see `PersonalFinanceTrakerApp.setupSampleDataIfNeeded`)
- **Access**: Via `TransactionRepository` which wraps `ModelContext`

### Key Architectural Patterns

#### 1. Repository Pattern
All data access goes through `ITransactionRepository`:
```swift
protocol ITransactionRepository {
    func fetchAll() throws -> [TransactionModel]
    func add(_ item: TransactionModel) throws
    func delete(_ item: TransactionModel) throws
    func update() throws
}
```

#### 2. Service Layer
Business logic extracted into services:
- `ChartDataService`: Transforms transactions into time-series data (Week: daily aggregation, Month: weekly, Year: monthly)
- `PieChartDataService`: Groups by category, calculates percentages, assigns colors
- `DateFormattingService`: Consistent date display with relative dates

#### 3. Component Composition
Features are broken down into reusable components within `Components/` subdirectories. Main feature views compose these smaller components.

#### 4. Amount Handling Convention
- **Storage**: `Decimal` type for financial precision
- **Sign Convention**: Income is positive, expenses are **negative**
- **Display**: Convert to `Double` in UI layer, show expenses as positive with appropriate labeling
- **Currency**: EUR hardcoded in display components

#### 5. State Management
- ViewModels use `@Published` properties
- Views use `@StateObject` for owned ViewModels or `@EnvironmentObject` for shared ones
- Combine framework for reactive pipelines (`AnyCancellable`, `sink`)
- Repository operations trigger `load()` which refreshes all computed state

### Feature Organization

Each feature under `/Features` follows this pattern:
```
FeatureName/
├── FeatureNameView.swift         # Main feature view
├── FeatureNameViewModel.swift    # Business logic and state
└── Components/                    # Feature-specific reusable components
    ├── ComponentA.swift
    └── ComponentB.swift
```

### Categories
Categories are defined statically in `TransactionCategory.swift`:
- **Expense categories**: 28 predefined (Groceries, Restaurants, Gas, Rent, etc.)
- **Income categories**: 8 predefined (Salary, Gift, Investment, etc.)
- Each category has an emoji and label
- Stored as string in `TransactionModel.category` (format: "emoji label")

### Time Periods
Three time periods supported (defined in `TimePeriod` enum):
- **Week**: Last 7 days, grouped by day
- **Month**: Last 30 days, grouped by week
- **Year**: Last 365 days, grouped by month

Chart data aggregation adjusts automatically based on selected period.

## Development Conventions

### File Organization
- Place new features in `/Features` with proper MVVM structure
- Extract reusable components into `Components/` subdirectory
- Models go in `/Models`, utilities/services in `/Utilities`
- Keep ViewModels separate from Views (no nested ViewModels inside View files)

### Naming Conventions
- ViewModels: `[Feature]ViewModel`
- Views: `[Feature]View` or `[Feature]MVVM` (for MVVM implementation)
- Components: Descriptive names like `TransactionItemView`, `CategoryDetailRow`
- Services: `[Purpose]Service` pattern

### Testing
- Uses Swift Testing framework (NOT XCTest)
- Import with `import Testing`
- Use `@Test` attribute for test functions
- Use `#expect(...)` for assertions
- Import app module with `@testable import PersonalFinanceTraker`

### SwiftUI Preview Pattern
All views should include `#Preview` blocks with in-memory ModelContainer for development:
```swift
#Preview {
    let container = try! ModelContainer(for: TransactionModel.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    SampleData.populateModelContext(container.mainContext)
    return YourView(context: container.mainContext)
        .modelContainer(container)
}
```

## Important Notes

- **Typo Alert**: Directory name is "PersonalFinanceTraker" (missing 'c' in Tracker)
- **Currency**: EUR is currently hardcoded throughout the app
- **Sample Data**: Available via `SampleData.populateModelContext()` for testing and previews
- **Navigation**: Uses `MainTabView` with tab-based navigation, modal sheets for forms
- The search tab exists but is not yet implemented (placeholder in `MainTabView`)

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
