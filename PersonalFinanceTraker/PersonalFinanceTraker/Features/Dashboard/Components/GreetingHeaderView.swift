//
//  GreetingHeaderView.swift
//  PersonalFinanceTraker
//

import SwiftUI

struct GreetingHeaderView: View {
    @Environment(ProfileViewModel.self) private var profileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profileViewModel.greeting)
                .font(.title2)
                .foregroundStyle(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

#Preview {
    GreetingHeaderView()
        .environment(ProfileViewModel())
}
