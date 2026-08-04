//
//  CreditView.swift
//  PersonalFinanceTraker
//

import SwiftUI
import SwiftData

struct CreditView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CreditViewModel
    @Binding var showingAddItemView: Bool

    init(context: ModelContext, showingAddItemView: Binding<Bool>) {
        _viewModel = State(wrappedValue: CreditViewModel(repo: CreditCardRepository(context: context)))
        _showingAddItemView = showingAddItemView
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.creditCards.isEmpty {
                        CreditUtilizationCard(
                            totalBalance: viewModel.totalBalance,
                            totalAvailable: viewModel.totalAvailable,
                            totalUtilization: viewModel.totalUtilization
                        )
                    }
                    CreditCardsSection(viewModel: viewModel)
                    Spacer(minLength: 80)
                }
                .padding(16)
            }
            .appBackground()
            .navigationTitle("Credit")
            .navigationBarTitleDisplayMode(.large)
            .appToolbar(showingAddItemView: $showingAddItemView)
        }
        .onAppear { viewModel.load() }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    let schema = Schema([TransactionModel.self, CategoryModel.self, CreditCardModel.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    do {
        let container = try ModelContainer(for: schema, configurations: [config])
        return AnyView(
            CreditView(context: container.mainContext, showingAddItemView: .constant(false))
                .modelContainer(container)
                .environment(ProfileViewModel())
                .preferredColorScheme(.dark)
        )
    } catch {
        return AnyView(Text("Preview failed: \(error.localizedDescription)"))
    }
}
