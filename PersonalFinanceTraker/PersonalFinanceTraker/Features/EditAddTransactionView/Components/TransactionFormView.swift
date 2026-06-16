import SwiftUI

struct TransactionFormView: View {
    @Bindable var viewModel: EditAddTransactionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section {
                    CurrencyAmountField(
                        label: "Amount",
                        placeholder: "0",
                        amount: $viewModel.amount,
                        currencyCode: $viewModel.currencyCode
                    )
                }
                .appFormSectionBackground()

                Section {
                    TextField("Note", text: $viewModel.transactionName, prompt: Text("Note"))
                        .submitLabel(.next)
                }
                .appFormSectionBackground()

                Section {
                    DatePicker(
                        "Date",
                        selection: $viewModel.date,
                        displayedComponents: [.date]
                    )
                    .tint(.accentIndigo)

                    Picker("Transaction Type", selection: $viewModel.transactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: viewModel.transactionType) { _, _ in
                        viewModel.selectedCategory = nil
                        viewModel.selectedGoal = nil
                    }

                    if viewModel.transactionType == .transfer {
                        Picker("Goal", selection: $viewModel.selectedGoal) {
                            Text("Select a goal").tag(GoalModel?.none)
                            ForEach(viewModel.availableGoals, id: \.id) { goal in
                                Text(goal.name).tag(GoalModel?.some(goal))
                            }
                        }
                        .tint(viewModel.selectedGoal == nil ? .secondary : .accentIndigo)
                    } else {
                        Picker("Category", selection: $viewModel.selectedCategory) {
                            Text("Select a category").tag(CategoryModel?.none)
                            ForEach(viewModel.filteredCategories) { category in
                                Label {
                                    Text(category.name)
                                } icon: {
                                    Image(systemName: category.systemImage)
                                        .foregroundStyle(category.categoryColor)
                                }
                                .tag(CategoryModel?.some(category))
                            }
                        }
                        .tint(viewModel.selectedCategory == nil ? .secondary : .accentIndigo)
                    }
                }
                .appFormSectionBackground()
            }
            .appFormBackground()
        }
    }
}
