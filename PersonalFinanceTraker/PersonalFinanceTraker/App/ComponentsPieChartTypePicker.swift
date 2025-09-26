//
//  PieChartTypePicker.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/09/25.
//

import SwiftUI

/// A reusable segmented picker component for selecting between expenses and income in pie charts
///
/// This component provides a consistent interface for users to switch between viewing
/// expense and income breakdowns in pie chart format.
///
/// ## Usage
/// ```swift
/// @State private var selectedDataType: PieChartDataType = .expenses
/// 
/// PieChartTypePicker(selection: $selectedDataType)
/// ```
///
/// ## Features
/// - Segmented control style for easy selection
/// - Consistent styling with other pickers in the app
/// - Clear labels for expenses vs income
public struct PieChartTypePicker: View {
    /// The currently selected pie chart data type
    @Binding public var selection: PieChartDataType
    
    /// Creates a new PieChartTypePicker
    /// - Parameter selection: A binding to the currently selected data type
    public init(selection: Binding<PieChartDataType>) {
        self._selection = selection
    }
    
    public var body: some View {
        Picker("Chart Type", selection: $selection) {
            Text("Expenses").tag(PieChartDataType.expenses)
            Text("Income").tag(PieChartDataType.income)
        }
        .pickerStyle(SegmentedPickerStyle())
    }
}

#Preview {
    @Previewable @State var selectedType: PieChartDataType = .expenses
    
    return VStack {
        PieChartTypePicker(selection: $selectedType)
        
        Text("Selected: \(selectedType.description)")
            .padding()
    }
    .padding()
}