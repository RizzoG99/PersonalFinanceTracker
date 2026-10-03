import SwiftUI
import Charts

/// What a category row drills into: that category's transactions for the period and type the
/// explorer was showing. A value, not a captured list, so the destination re-derives its rows.
struct ExplorerDrillDown: Hashable {
    let category: String
    let interval: DateInterval
    let dataType: PieChartDataType
    let periodLabel: String
}

/// Insights' breakdown explorer (#187): one period navigator driving a bar chart of the period,
/// a pie of category shares and the category list with Δ vs the previous period.
struct BreakdownExplorerSection: View {
    @Bindable var viewModel: CompassViewModel
    @State private var showingCustomRange = false

    private var period: ExplorerPeriod { viewModel.explorerPeriod }
    private var breakdown: ExplorerBreakdown { viewModel.explorer }
    private var isIncome: Bool { viewModel.explorerType == .income }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Breakdown")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Text("Where your money goes")
                    .font(.caption)
                    .foregroundStyle(.textDim)
            }

            GlassCard {
                VStack(spacing: 16) {
                    navigator
                    PieChartTypePicker(selection: $viewModel.explorerType)
                    if breakdown.trends.isEmpty {
                        ContentUnavailableView(
                            isIncome ? "No income in \(period.label)" : "No expenses in \(period.label)",
                            systemImage: "chart.pie",
                            description: Text("Try another period with the arrows above.")
                        )
                    } else {
                        Text(breakdown.total.formattedEUR())
                            .font(.title2.bold())
                            .foregroundStyle(.textPrimary)
                            .privacyBlur()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        bars
                        CategoryPieChart(data: breakdown.trends.map(\.category))
                    }
                }
            }

            VStack(spacing: 8) {
                ForEach(breakdown.trends) { trend in
                    NavigationLink(value: ExplorerDrillDown(
                        category: trend.category.category,
                        interval: period.interval,
                        dataType: viewModel.explorerType,
                        periodLabel: period.label
                    )) {
                        CategoryTrendRow(trend: trend, isIncome: isIncome)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the transactions in this category")
                }
            }
        }
        .sheet(isPresented: $showingCustomRange) {
            CustomRangeSheet(initial: period.interval, earliest: viewModel.firstTransactionDate) { viewModel.explorerPeriod = $0 }
                .presentationDetents([.medium, .large])
                .presentationBackground { AppBackground() }
        }
    }

    private var navigator: some View {
        HStack {
            Button("Previous period", systemImage: "chevron.left") {
                viewModel.explorerPeriod = period.previous()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(!viewModel.canGoToPreviousPeriod)

            Spacer()

            Menu {
                Picker("Period", selection: Binding(
                    get: { period.granularity },
                    // Stay around the date being viewed: Sep 2025 → Year shows 2025, not this year.
                    set: { viewModel.explorerPeriod = .current($0, now: period.interval.start) }
                )) {
                    ForEach(ExplorerPeriod.Granularity.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) }
                }
                // A button, not a picker option: re-picking "Custom" while already on a custom
                // range sets the same value, so a picker would never reopen the sheet to edit it.
                Button("Custom range…", systemImage: period.granularity == .custom ? "checkmark" : "calendar") {
                    showingCustomRange = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(period.label)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.textPrimary)
                .frame(minHeight: 44)
            }
            .accessibilityLabel(period.label)
            .accessibilityHint("Changes between week, month, year or a custom range")

            Spacer()

            Button("Next period", systemImage: "chevron.right") {
                viewModel.explorerPeriod = period.next()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(period.isCurrent())
        }
        .font(.body.bold())
        .tint(.accentIndigo)
    }

    private var bars: some View {
        Chart(breakdown.bars) { bar in
            BarMark(
                x: .value("Date", bar.date, unit: breakdown.barUnit),
                y: .value("Amount", Double(truncating: bar.amount as NSDecimalNumber))
            )
            .foregroundStyle(Color.accentIndigo)
            .cornerRadius(2)
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(.textDim)
                AxisGridLine().foregroundStyle(Color.hairline)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(.textDim)
            }
        }
        .frame(height: 140)
        .privacyBlur()
    }
}

/// Custom range picker: two dates, applied as whole days (from's day through to's day).
private struct CustomRangeSheet: View {
    let onApply: (ExplorerPeriod) -> Void
    /// Start of the first transaction's day: earlier dates can only ever show an empty range.
    let earliest: Date
    @State private var from: Date
    @State private var to: Date
    @Environment(\.dismiss) private var dismiss

    init(initial: DateInterval, earliest firstTransaction: Date?, onApply: @escaping (ExplorerPeriod) -> Void) {
        self.onApply = onApply
        let earliest = Calendar.current.startOfDay(for: min(firstTransaction ?? .now, .now))
        self.earliest = earliest
        let to = max(earliest, min(.now, initial.end.addingTimeInterval(-1)))
        _from = State(initialValue: min(to, max(earliest, initial.start)))
        _to = State(initialValue: to)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, in: earliest...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from...Date.now, displayedComponents: .date)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(.custom(from: from, through: to))
                        dismiss()
                    }
                }
            }
        }
    }
}
