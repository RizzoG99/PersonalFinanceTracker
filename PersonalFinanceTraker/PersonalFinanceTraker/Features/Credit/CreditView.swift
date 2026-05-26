//
//  CreditView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct CreditView: View {
    @Binding var showingAddItemView: Bool
    @State private var creditScore: Int = 742
    @State private var creditStatus: String = "Good"
    @State private var totalUtilization: Double = 0.35

    init(showingAddItemView: Binding<Bool>) {
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CreditScoreCard(creditScore: creditScore, creditStatus: creditStatus)
                    CreditUtilizationCard(totalUtilization: totalUtilization)
                    CreditCardsSection()
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle("Credit")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
    }

}

#Preview {
    CreditView(showingAddItemView: .constant(false))
        .environmentObject(ProfileViewModel())
        .preferredColorScheme(.dark)
}
