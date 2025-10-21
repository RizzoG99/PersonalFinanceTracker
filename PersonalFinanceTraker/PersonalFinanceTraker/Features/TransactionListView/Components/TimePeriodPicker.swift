//
//  TimePeriodPicker.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

/// Represents different time periods for financial data analysis
public enum TimePeriod: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    
    /// Number of days represented by each time period
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }
    
    /// Human-readable description of the time period
    var description: String {
        return rawValue
    }
}

/// A reusable segmented picker component for selecting time periods in financial views
///
/// This component provides a consistent interface for users to select between different
/// time periods (week, month, year) for viewing financial data and charts.
///
/// ## Usage
/// ```swift
/// @State private var selectedPeriod: TimePeriod = .month
/// 
/// TimePeriodPicker(selection: $selectedPeriod)
/// ```
///
/// ## Features
/// - Segmented control style for easy selection
/// - Consistent styling across the app
/// - Supports all common time periods for financial analysis
public struct TimePeriodPicker: View {
    /// The currently selected time period
    @Binding public var selection: TimePeriod
    
    /// Creates a new TimePeriodPicker
    /// - Parameter selection: A binding to the currently selected time period
    public init(selection: Binding<TimePeriod>) {
        self._selection = selection
    }
    
    public var body: some View {
        Picker("Time Period", selection: $selection) {
            ForEach(TimePeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
}

#Preview {
    @Previewable @State var selectedPeriod: TimePeriod = .month
    
    return VStack {
        TimePeriodPicker(selection: $selectedPeriod)
        
        Text("Selected: \(selectedPeriod.rawValue)")
            .padding()
    }
    .padding()
}
