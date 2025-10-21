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
        HStack {
            // Color indicator
            Circle()
                .fill(dataPoint.color)
                .frame(width: 16, height: 16)
            
            // Category name
            Text(dataPoint.category)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            // Amount and percentage
            VStack(alignment: .trailing, spacing: 2) {
                Text(dataPoint.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(dataPoint.formattedPercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
