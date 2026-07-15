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
                        currencyCode: $viewModel.currencyCode,
                        shouldAutoFocus: viewModel.editingItem == nil
                    )
                }
                .appFormSectionBackground()

                Section {
                    Picker("Type", selection: $viewModel.transactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.transactionType) { _, _ in
                        viewModel.selectedCategory = nil
                        viewModel.selectedGoal = nil
                    }
                }
                .appFormSectionBackground()

                Section {
                    TextField("Name", text: $viewModel.transactionName, prompt: Text("Name (e.g. Groceries)"))
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
                }
                .appFormSectionBackground()

                if viewModel.transactionType == .transfer {
                    Section {
                        GoalChipsGrid(
                            availableGoals: viewModel.availableGoals,
                            selectedGoal: $viewModel.selectedGoal
                        )
                    } header: {
                        Text("Goal")
                    }
                    .appFormSectionBackground()
                } else {
                    Section {
                        CategoryChipsGrid(
                            categories: viewModel.filteredCategories,
                            selectedCategory: $viewModel.selectedCategory
                        )
                    } header: {
                        Text("Category")
                    }
                    .appFormSectionBackground()
                }
            }
            .appFormBackground()
        }
    }
}

// MARK: - Category Chips Grid

struct CategoryChipsGrid: View {
    let categories: [CategorySnapshot]
    @Binding var selectedCategory: CategorySnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 80), spacing: 8),
                GridItem(.flexible(minimum: 80), spacing: 8),
                GridItem(.flexible(minimum: 80), spacing: 8)
            ], spacing: 8) {
                ForEach(categories) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory?.persistentId == category.persistentId
                    )
                    .onTapGesture {
                        selectedCategory = category
                    }
                }
            }
        }
    }
}

struct CategoryChip: View {
    let category: CategorySnapshot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(category.categoryColor)

            Text(category.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? category.categoryColor.opacity(0.2)
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? category.categoryColor : Color.textDim.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .cornerRadius(12)
    }
}

// MARK: - Goal Chips Grid

struct GoalChipsGrid: View {
    let availableGoals: [GoalSnapshot]
    @Binding var selectedGoal: GoalSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 80), spacing: 8),
                GridItem(.flexible(minimum: 80), spacing: 8),
                GridItem(.flexible(minimum: 80), spacing: 8)
            ], spacing: 8) {
                ForEach(availableGoals) { goal in
                    GoalChip(
                        goal: goal,
                        isSelected: selectedGoal?.id == goal.id
                    )
                    .onTapGesture {
                        selectedGoal = goal
                    }
                }
            }
        }
    }
}

struct GoalChip: View {
    let goal: GoalSnapshot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: goal.iconName)
                .font(.system(size: 20))
                .foregroundStyle(goal.goalColor)

            Text(goal.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            isSelected
                ? goal.goalColor.opacity(0.2)
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? goal.goalColor : Color.textDim.opacity(0.3),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .cornerRadius(12)
    }
}
