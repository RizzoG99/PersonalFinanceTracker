//
//  CategoryDetailRow.swift
//  PersonalFinanceTraker
//
//  Created by Gabriele Rizzo on 21/10/25.
//

import SwiftUI


/// A detailed row for each category in the breakdown
struct CategoryDetailRow: View {
    let dataPoint: PieChartDataPoint
    let currencyCode: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Color indicator
                Circle()
                    .fill(dataPoint.color)
                    .frame(width: 16, height: 16)
                
                // Category name
                Text(dataPoint.category.removingLeadingEmoji)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Amount and percentage
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dataPoint.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .privacyBlur()
                    
                    Text(dataPoint.formattedPercentage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Budget Progress Bar
            if let usage = dataPoint.budgetUsage, let budget = dataPoint.budget {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(progressBarColor(usage: usage))
                                .frame(width: min(geometry.size.width * CGFloat(usage), geometry.size.width), height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text("\(Int(usage * 100))% of budget spent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("Budget: \(budget, format: .currency(code: currencyCode).precision(.fractionLength(0)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .privacyBlur()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func progressBarColor(usage: Double) -> Color {
        if usage >= 1.0 {
            return .red
        } else if usage >= 0.8 {
            return .orange
        } else {
            return .green
        }
    }
}
